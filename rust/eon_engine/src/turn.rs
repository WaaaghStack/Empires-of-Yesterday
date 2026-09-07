//! The World turn — the ordered order-of-operations pipeline (WEGO-resolvable).
//!
//! One `run_turn` folds a fixed sequence of phases; each phase posts to the ledger. A light,
//! fully deterministic AI generates orders so a turn can resolve headlessly and reproducibly.
//! The turn projects a wide-row `TurnReport` that must reconcile with the ledger aggregates.

use crate::battle::{self, BattleReport};
use crate::dominion;
use crate::ledger::{Account, Ledger, Phase};
use crate::model::{FactionId, GemPath, ProvinceId, UnitKind, World};

const BASELINE_GEM: f64 = 1.0;
const SOLDIER_UPKEEP_VE: f64 = 0.05; // bombers have NO upkeep (design lock A14 preserved)
const RITUAL_COST_AU: f64 = 6.0;
const RITUAL_SURGE: f32 = 10.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VictoryKind {
    Conquest,
    DominionKill,
    Ascension,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Ongoing,
    Victory(FactionId, VictoryKind),
}

/// Wide-row projection of the turn (the report the presentation layer renders).
#[derive(Clone, Debug)]
pub struct ProvinceRow {
    pub province: ProvinceId,
    pub owner: Option<FactionId>,
    pub dom: Vec<f32>,
    pub unrest: f32,
}

#[derive(Clone, Debug)]
pub struct FactionRow {
    pub faction: FactionId,
    pub total_dominion: f32,
    pub owned_land: u32,
    pub units_alive: u32,
    pub gems: Vec<(GemPath, f32)>,
    pub ascension: u32,
    pub alive: bool,
}

#[derive(Clone, Debug)]
pub struct TurnReport {
    pub turn: u32,
    pub provinces: Vec<ProvinceRow>,
    pub factions: Vec<FactionRow>,
    pub battles: Vec<BattleReport>,
    pub outcome: Outcome,
}

impl TurnReport {
    /// The report must tie out to the ledger (trial-balance reconciliation).
    pub fn reconcile(&self, world: &World, ledger: &Ledger) -> bool {
        // Books balance.
        if ledger.trial_balance().abs() >= 1e-3 {
            return false;
        }
        for fr in &self.factions {
            let f = fr.faction;
            // Dominion aggregate == summed province dominion (report) == ledger account.
            // Tolerance accounts for accumulated f32 rounding vs the f64 ledger aggregate.
            let ledger_dom = ledger.balance(Account::Dominion(f)) as f32;
            let tol = 0.5 + 0.01 * ledger_dom.abs();
            if (ledger_dom - fr.total_dominion).abs() > tol {
                return false;
            }
            if (ledger_dom - world.total_dominion(f)).abs() > tol {
                return false;
            }
            // Units alive matches the ledger.
            if (ledger.balance(Account::UnitsAlive(f)) as i64 - fr.units_alive as i64).abs() > 0 {
                return false;
            }
        }
        true
    }
}

/// Resolve one full turn. Deterministic given `world.seed`.
pub fn run_turn(world: &mut World, ledger: &mut Ledger) -> TurnReport {
    world.turn += 1;
    generate_ai_orders(world);

    income_phase(world, ledger);
    upkeep_phase(world, ledger);
    crate::agents::agents_phase(world, ledger, world.seed);
    rituals_phase(world, ledger);
    movement_phase(world);
    let battles = battles_phase(world, ledger);
    dominion::dominion_phase(world, ledger);
    dominion::corruption_phase(world, ledger);
    events_phase(world);
    let outcome = win_check(world);

    make_report(world, ledger, battles, outcome)
}

/// Income: baseline gems + owned gem deposits (minted from GemSource, balanced).
fn income_phase(world: &mut World, ledger: &mut Ledger) {
    let cfg = world.cfg.clone();
    let fc = world.faction_count();
    // Baseline per faction per path.
    for f in 0..fc {
        for path in GemPath::all() {
            ledger.post(
                world.turn,
                Phase::Income,
                "baseline_gems",
                vec![
                    (Account::Gems(f as FactionId, path), BASELINE_GEM),
                    (Account::GemSource(f as FactionId), -BASELINE_GEM),
                ],
                format!("baseline f{f} {}", path.as_str()),
            );
        }
    }
    // Deposits credit their owner.
    for pid in 0..world.provinces.len() {
        let (owner, deposit) = {
            let p = &world.provinces[pid];
            (p.owner(&cfg), p.deposit)
        };
        if let (Some(o), Some(path)) = (owner, deposit) {
            ledger.post(
                world.turn,
                Phase::Income,
                "deposit_gems",
                vec![
                    (Account::Gems(o, path), cfg.gem_per_deposit as f64),
                    (Account::GemSource(o), -(cfg.gem_per_deposit as f64)),
                ],
                format!("deposit prov{pid} f{o} {}", path.as_str()),
            );
        }
    }
    ledger.assert_balanced();
}

/// Upkeep: soldiers cost Verdantite; shortfall causes attrition. Bombers cost nothing (A14).
fn upkeep_phase(world: &mut World, ledger: &mut Ledger) {
    let fc = world.faction_count();
    for f in 0..fc {
        let fid = f as FactionId;
        let soldiers: u32 = world
            .armies
            .iter()
            .filter(|a| a.faction == fid)
            .flat_map(|a| a.squads.iter())
            .filter(|s| s.kind == UnitKind::Soldier)
            .map(|s| s.count)
            .sum();
        if soldiers == 0 {
            continue;
        }
        let cost = soldiers as f64 * SOLDIER_UPKEEP_VE;
        let avail = ledger.balance(Account::Gems(fid, GemPath::Verdantite)).max(0.0);
        let pay = cost.min(avail);
        if pay > 0.0 {
            ledger.post(
                world.turn,
                Phase::Upkeep,
                "upkeep_pay",
                vec![
                    (Account::Gems(fid, GemPath::Verdantite), -pay),
                    (Account::GemSource(fid), pay),
                ],
                format!("upkeep f{fid} pay {pay:.2}"),
            );
        }
        let shortfall = cost - pay;
        if shortfall > 1e-6 {
            // Attrition: lose one soldier per unpaid upkeep unit (deterministic front-first).
            let mut loss = (shortfall / SOLDIER_UPKEEP_VE).floor() as u32;
            loss = loss.min(soldiers);
            let mut remaining = loss;
            for army in world.armies.iter_mut().filter(|a| a.faction == fid) {
                for sq in army.squads.iter_mut().filter(|s| s.kind == UnitKind::Soldier) {
                    if remaining == 0 {
                        break;
                    }
                    let take = remaining.min(sq.count);
                    sq.count -= take;
                    remaining -= take;
                }
            }
            if loss > 0 {
                ledger.post(
                    world.turn,
                    Phase::Upkeep,
                    "attrition",
                    vec![
                        (Account::UnitsAlive(fid), -(loss as f64)),
                        (Account::Casualties(fid), loss as f64),
                    ],
                    format!("attrition f{fid} lost {loss}"),
                );
            }
        }
    }
    world.armies.retain(|a| !a.is_empty());
    ledger.assert_balanced();
}

/// A simple ritual: spend Aurelium to consecrate the capital (a manual Surge).
fn rituals_phase(world: &mut World, ledger: &mut Ledger) {
    let fc = world.faction_count();
    for f in 0..fc {
        let fid = f as FactionId;
        if ledger.balance(Account::Gems(fid, GemPath::Aurelium)) < RITUAL_COST_AU {
            continue;
        }
        // Find this faction's capital province.
        let cap = world.provinces.iter().position(|p| p.capital_of == Some(fid));
        if let Some(pid) = cap {
            ledger.post(
                world.turn,
                Phase::Rituals,
                "ritual_spend",
                vec![
                    (Account::Gems(fid, GemPath::Aurelium), -RITUAL_COST_AU),
                    (Account::GemSource(fid), RITUAL_COST_AU),
                ],
                format!("ritual f{fid} surge"),
            );
            world.provinces[pid].dom[fid as usize] += RITUAL_SURGE;
            ledger.post(
                world.turn,
                Phase::Rituals,
                "ritual_surge",
                vec![
                    (Account::Dominion(fid), RITUAL_SURGE as f64),
                    (Account::DominionSource(fid), -(RITUAL_SURGE as f64)),
                ],
                format!("surge f{fid} @prov{pid}"),
            );
        }
    }
    ledger.assert_balanced();
}

/// Apply one-step army movement orders. Head-on enemy swaps (A: x→y while B: y→x) would trade
/// places forever without meeting, so we cancel the higher-faction-id army's move — it stands its
/// ground and the other marches in, producing a battle.
fn movement_phase(world: &mut World) {
    let intents: Vec<(usize, ProvinceId, ProvinceId, FactionId)> = world
        .armies
        .iter()
        .enumerate()
        .filter_map(|(i, a)| a.move_to.map(|dst| (i, a.province, dst, a.faction)))
        .collect();
    for a in 0..intents.len() {
        for b in 0..intents.len() {
            let (ia, ca, da, fa) = intents[a];
            let (ib, cb, db, fb) = intents[b];
            if fa != fb && da == cb && db == ca {
                let loser = if fa >= fb { ia } else { ib };
                world.armies[loser].move_to = None;
            }
        }
    }
    for i in 0..world.armies.len() {
        if let Some(dst) = world.armies[i].move_to.take() {
            let cur = world.armies[i].province;
            if world.provinces[cur as usize].neighbors.contains(&dst)
                && world.provinces[dst as usize].is_land
            {
                world.armies[i].province = dst;
            }
        }
    }
}

/// Resolve battles in every province that now holds armies of both factions (2-faction MVP).
fn battles_phase(world: &mut World, ledger: &mut Ledger) -> Vec<BattleReport> {
    let mut reports = Vec::new();
    let n = world.provinces.len();
    for pid in 0..n {
        let f0 = world
            .armies
            .iter()
            .any(|a| a.province == pid as ProvinceId && a.faction == 0 && !a.is_empty());
        let f1 = world
            .armies
            .iter()
            .any(|a| a.province == pid as ProvinceId && a.faction == 1 && !a.is_empty());
        if f0 && f1 {
            reports.push(battle::resolve_battle_in_province(
                world,
                ledger,
                pid as ProvinceId,
                0,
                1,
                world.seed,
            ));
        }
    }
    reports
}

/// Ascension points = owned thrones; refresh faction alive flags.
fn events_phase(world: &mut World) {
    let cfg = world.cfg.clone();
    for f in 0..world.faction_count() {
        let fid = f as FactionId;
        let thrones = world.owned_thrones(fid);
        world.factions[f].ascension_points = thrones;
        let alive = world.total_dominion(fid) > cfg.dominion_alive_eps
            || world.armies.iter().any(|a| a.faction == fid && !a.is_empty());
        world.factions[f].alive = alive;
    }
}

fn win_check(world: &World) -> Outcome {
    let cfg = &world.cfg;
    let fc = world.faction_count();
    let land = world.land_count();
    // Ascension.
    for f in 0..fc {
        if world.factions[f].ascension_points >= cfg.thrones_to_win {
            return Outcome::Victory(f as FactionId, VictoryKind::Ascension);
        }
    }
    // Conquest.
    for f in 0..fc {
        if land > 0 && world.owned_land(f as FactionId) == land {
            return Outcome::Victory(f as FactionId, VictoryKind::Conquest);
        }
    }
    // Dominion kill: exactly one faction with meaningful faith left.
    let alive_faith: Vec<FactionId> = (0..fc)
        .filter(|&f| world.total_dominion(f as FactionId) > cfg.dominion_alive_eps)
        .map(|f| f as FactionId)
        .collect();
    if alive_faith.len() == 1 {
        return Outcome::Victory(alive_faith[0], VictoryKind::DominionKill);
    }
    Outcome::Ongoing
}

fn make_report(
    world: &World,
    ledger: &Ledger,
    battles: Vec<BattleReport>,
    outcome: Outcome,
) -> TurnReport {
    let cfg = &world.cfg;
    let provinces = world
        .provinces
        .iter()
        .map(|p| ProvinceRow {
            province: p.id,
            owner: p.owner(cfg),
            dom: p.dom.clone(),
            unrest: p.unrest,
        })
        .collect();
    let factions = (0..world.faction_count())
        .map(|f| {
            let fid = f as FactionId;
            let units: u32 = world
                .armies
                .iter()
                .filter(|a| a.faction == fid)
                .map(|a| a.total_units())
                .sum();
            FactionRow {
                faction: fid,
                total_dominion: world.total_dominion(fid),
                owned_land: world.owned_land(fid) as u32,
                units_alive: units,
                gems: GemPath::all()
                    .iter()
                    .map(|&p| (p, ledger.balance(Account::Gems(fid, p)) as f32))
                    .collect(),
                ascension: world.factions[f].ascension_points,
                alive: world.factions[f].alive,
            }
        })
        .collect();
    TurnReport { turn: world.turn, provinces, factions, battles, outcome }
}

/// A minimal deterministic AI: expand armies toward non-owned neighbors; push prophets to the
/// frontier; aim spies at adjacent enemy provinces. Enough to make turns evolve reproducibly.
fn generate_ai_orders(world: &mut World) {
    let cfg = world.cfg.clone();
    // Armies: attack into an adjacent enemy-held province if one exists (guarantees contact);
    // otherwise expand toward the lowest-id neighbor not owned by self.
    for i in 0..world.armies.len() {
        let (fac, prov) = (world.armies[i].faction, world.armies[i].province);
        let mut neigh = world.provinces[prov as usize].neighbors.clone();
        neigh.sort_unstable();
        // Prefer a neighbor that holds an enemy army.
        let attack = neigh.iter().copied().find(|&nb| {
            world
                .armies
                .iter()
                .any(|a| a.province == nb && a.faction != fac && !a.is_empty())
        });
        let order = attack.or_else(|| {
            neigh
                .iter()
                .copied()
                .find(|&nb| world.provinces[nb as usize].owner(&cfg) != Some(fac))
        });
        world.armies[i].move_to = order;
    }
    // Prophets: move to the neighbor where our faith is weakest (spread frontier). Spies: target
    // an adjacent province owned by someone else.
    for i in 0..world.agents.len() {
        if !world.agents[i].alive {
            continue;
        }
        let (fac, prov, kind) = {
            let a = &world.agents[i];
            (a.faction, a.province, a.kind)
        };
        let mut neigh = world.provinces[prov as usize].neighbors.clone();
        neigh.sort_unstable();
        match kind {
            crate::model::AgentKind::Prophet | crate::model::AgentKind::Priest => {
                let mut best = None;
                let mut best_dom = f32::MAX;
                for nb in &neigh {
                    let d = world.provinces[*nb as usize].dom[fac as usize];
                    if d < best_dom {
                        best_dom = d;
                        best = Some(*nb);
                    }
                }
                world.agents[i].move_to = best;
                world.agents[i].target = None;
            }
            _ => {
                let tgt = neigh
                    .iter()
                    .find(|&&nb| {
                        let o = world.provinces[nb as usize].owner(&cfg);
                        o.is_some() && o != Some(fac)
                    })
                    .copied()
                    .or(Some(prov));
                world.agents[i].target = tgt;
                world.agents[i].move_to = None;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scenario;

    #[test]
    fn turn_runs_and_reconciles() {
        let (mut w, mut l) = scenario::demo_world(2024);
        for _ in 0..12 {
            let r = run_turn(&mut w, &mut l);
            assert!(r.reconcile(&w, &l), "turn {} report must reconcile with the ledger", r.turn);
        }
    }

    #[test]
    fn full_campaign_is_deterministic() {
        let run = || {
            let (mut w, mut l) = scenario::demo_world(7);
            for _ in 0..25 {
                run_turn(&mut w, &mut l);
            }
            (w.digest(), l.digest())
        };
        assert_eq!(run(), run(), "same seed → identical campaign world + journal");
    }

    #[test]
    fn dominion_kill_can_win() {
        // Faction 0 has faith; faction 1 has none. A neutral province keeps conquest from firing
        // first, so the win must come from dominion-kill.
        let (mut w, mut l) = scenario::duel_line(3, 3);
        w.provinces[2].capital_of = None; // remove enemy source so f1 never gains faith
        w.provinces[0].capital_of = Some(0);
        scenario::seed_dominion(&mut w, &mut l, 0, 0, 20.0);
        scenario::seed_dominion(&mut w, &mut l, 1, 0, 20.0);
        let mut won = false;
        for _ in 0..30 {
            let r = run_turn(&mut w, &mut l);
            if let Outcome::Victory(0, VictoryKind::DominionKill) = r.outcome {
                won = true;
                break;
            }
        }
        assert!(won, "faction 0 should win by dominion kill when only it has faith");
    }

    #[test]
    fn bombers_have_no_upkeep() {
        // A bomber-only army must never take upkeep attrition even with zero gems.
        let (mut w, mut l) = scenario::duel_line(2, 1);
        scenario::recruit_army(&mut w, &mut l, 0, 0, vec![crate::model::Squad {
            kind: UnitKind::Bomber,
            count: 20,
        }]);
        // Drain any Verdantite so upkeep would bite a soldier army.
        let before = w.armies[0].total_units();
        upkeep_phase(&mut w, &mut l);
        assert_eq!(w.armies[0].total_units(), before, "bombers have no continuous upkeep (A14)");
    }
}
