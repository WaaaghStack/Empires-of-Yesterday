//! The Dominion field phase — the "faith tide".
//!
//! Runs as a single scheduled phase in the order of operations (see `eoy-sim-transaction-engine`
//! § fields-vs-entities): the per-province field is an array/graph kernel, not per-tile
//! transactions. Properties requested by design:
//! - **Passive baseline + amplifiers**: capitals/temples/prophets/priests inject dominion.
//! - **Height-independent**: diffusion ignores elevation entirely (only water blocks).
//! - **Slow**: low spread rate → a creeping tide, not a flood.
//! - **Cancellation**: opposing faith erodes on contact.
//! Injection (mint) and cancellation (destroy) post to the ledger; diffusion conserves per-faction
//! mass and therefore posts nothing (it is a spatial redistribution of already-credited mass).

use crate::ledger::{Account, Ledger, Phase};
use crate::model::{AgentKind, FactionId, World};

/// Injection + diffusion + cancellation for one turn.
pub fn dominion_phase(world: &mut World, ledger: &mut Ledger) {
    inject_sources(world, ledger);
    diffuse(world);
    cancel_contested(world, ledger);
    world.provinces
        .iter_mut()
        .for_each(|p| p.dom.iter_mut().for_each(|d| *d = d.max(0.0)));
    ledger.assert_balanced();
}

/// Capitals + temples (fixed) and prophets/priests (mobile) mint dominion into their province.
fn inject_sources(world: &mut World, ledger: &mut Ledger) {
    let cfg = world.cfg.clone();
    let turn = world.turn;

    // Fixed sources: capital + temple.
    for p in world.provinces.iter_mut() {
        if !p.is_land {
            continue;
        }
        if let Some(f) = p.capital_of {
            p.dom[f as usize] += cfg.capital_output;
            ledger.post(
                turn,
                Phase::Dominion,
                "inject_capital",
                vec![
                    (Account::Dominion(f), cfg.capital_output as f64),
                    (Account::DominionSource(f), -(cfg.capital_output as f64)),
                ],
                format!("prov {} capital f{}", p.id, f),
            );
        }
        if let Some(f) = p.temple_owner {
            p.dom[f as usize] += cfg.temple_output;
            ledger.post(
                turn,
                Phase::Dominion,
                "inject_temple",
                vec![
                    (Account::Dominion(f), cfg.temple_output as f64),
                    (Account::DominionSource(f), -(cfg.temple_output as f64)),
                ],
                format!("prov {} temple f{}", p.id, f),
            );
        }
    }

    // Mobile amplifiers: prophets/priests standing in a province.
    for i in 0..world.agents.len() {
        let ag = &world.agents[i];
        if !ag.alive {
            continue;
        }
        let output = match ag.kind {
            AgentKind::Prophet => cfg.prophet_output,
            AgentKind::Priest => cfg.priest_output,
            _ => continue,
        };
        let f = ag.faction;
        let pid = ag.province as usize;
        if !world.provinces[pid].is_land {
            continue;
        }
        world.provinces[pid].dom[f as usize] += output;
        ledger.post(
            turn,
            Phase::Dominion,
            "inject_amplifier",
            vec![
                (Account::Dominion(f), output as f64),
                (Account::DominionSource(f), -(output as f64)),
            ],
            format!("prov {} {} f{}", pid, ag.kind.as_str(), f),
        );
    }
}

/// Edge-based, mass-conserving diffusion across land neighbors. Height-independent.
fn diffuse(world: &mut World) {
    let n = world.provinces.len();
    let fc = world.faction_count();
    let rate = world.cfg.dominion_spread_rate;
    // Accumulate deltas so ordering cannot bias the result; each undirected edge processed once.
    let mut delta = vec![0.0f32; n * fc];
    for a in 0..n {
        if !world.provinces[a].is_land {
            continue;
        }
        // Sorted neighbor order + b > a → each edge exactly once, deterministic.
        let neighbors = world.provinces[a].neighbors.clone();
        for &b_id in &neighbors {
            let b = b_id as usize;
            if b <= a || !world.provinces[b].is_land {
                continue;
            }
            for f in 0..fc {
                let da = world.provinces[a].dom[f];
                let db = world.provinces[b].dom[f];
                // Move half the rate-scaled gradient across the edge (symmetric, conserving).
                let transfer = rate * (da - db) * 0.5;
                delta[a * fc + f] -= transfer;
                delta[b * fc + f] += transfer;
            }
        }
    }
    for p in 0..n {
        for f in 0..fc {
            world.provinces[p].dom[f] += delta[p * fc + f];
        }
    }
}

/// Opposing faith erodes on contact. All eroded mass is posted to the sink so the books balance.
fn cancel_contested(world: &mut World, ledger: &mut Ledger) {
    let cfg = world.cfg.clone();
    let turn = world.turn;
    let fc = world.faction_count();
    for pid in 0..world.provinces.len() {
        if !world.provinces[pid].is_land {
            continue;
        }
        // Leader = strongest faith here.
        let mut leader: Option<FactionId> = None;
        let mut leader_val = 0.0f32;
        for f in 0..fc {
            let d = world.provinces[pid].dom[f];
            if leader.is_none() || d > leader_val {
                leader = Some(f as FactionId);
                leader_val = d;
            }
        }
        let leader = match leader {
            Some(l) if leader_val > 0.0 => l,
            _ => continue,
        };
        let contested: f32 = (0..fc)
            .filter(|&f| f as FactionId != leader)
            .map(|f| world.provinces[pid].dom[f])
            .sum();
        if contested <= 0.0 {
            continue;
        }
        let mut postings: Vec<(Account, f64)> = Vec::new();
        let mut sink = 0.0f64;
        // Each opposing faith erodes proportionally; leader erodes by the contested pressure.
        for f in 0..fc {
            let fid = f as FactionId;
            if fid == leader {
                continue;
            }
            let d = world.provinces[pid].dom[f];
            if d <= 0.0 {
                continue;
            }
            let erosion = cfg.cancel_rate * d;
            world.provinces[pid].dom[f] -= erosion;
            postings.push((Account::Dominion(fid), -(erosion as f64)));
            sink += erosion as f64;
        }
        let leader_erosion = cfg.cancel_rate * leader_val.min(contested);
        world.provinces[pid].dom[leader as usize] -= leader_erosion;
        postings.push((Account::Dominion(leader), -(leader_erosion as f64)));
        sink += leader_erosion as f64;

        if sink > 0.0 {
            postings.push((Account::DominionSink, sink));
            ledger.post(
                turn,
                Phase::Dominion,
                "cancel",
                postings,
                format!("prov {pid} contested"),
            );
        }
    }
}

/// Corruption/unrest: enemy faith in an owned province breeds unrest; high unrest erodes the
/// owner's own faith (a real feedback, posted to the sink so the ledger stays balanced).
pub fn corruption_phase(world: &mut World, ledger: &mut Ledger) {
    let cfg = world.cfg.clone();
    let turn = world.turn;
    let fc = world.faction_count();
    for pid in 0..world.provinces.len() {
        if !world.provinces[pid].is_land {
            world.provinces[pid].unrest *= 1.0 - cfg.unrest_decay;
            continue;
        }
        let owner = world.provinces[pid].owner(&cfg);
        let enemy_dom: f32 = match owner {
            Some(o) => (0..fc)
                .filter(|&f| f as FactionId != o)
                .map(|f| world.provinces[pid].dom[f])
                .sum(),
            None => (0..fc).map(|f| world.provinces[pid].dom[f]).sum(),
        };
        let p = &mut world.provinces[pid];
        p.unrest += cfg.unrest_from_enemy * enemy_dom;
        p.unrest -= cfg.unrest_decay * p.unrest;
        if p.unrest < 0.0 {
            p.unrest = 0.0;
        }
        if let Some(o) = owner {
            if p.unrest > cfg.unrest_threshold {
                let erosion = cfg.unrest_faith_erosion.min(p.dom[o as usize]);
                if erosion > 0.0 {
                    p.dom[o as usize] -= erosion;
                    ledger.post(
                        turn,
                        Phase::Corruption,
                        "unrest_erosion",
                        vec![
                            (Account::Dominion(o), -(erosion as f64)),
                            (Account::DominionSink, erosion as f64),
                        ],
                        format!("prov {pid} unrest {:.1}", p.unrest),
                    );
                }
            }
        }
    }
    ledger.assert_balanced();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scenario;

    #[test]
    fn injection_increases_and_reconciles() {
        let (mut w, mut l) = scenario::duel_line(5, 1234);
        let before = w.total_dominion(0);
        inject_sources(&mut w, &mut l);
        assert!(w.total_dominion(0) > before, "capital should mint faith");
        // Ledger aggregate matches summed province dominion (reconciliation).
        let ledger_agg = l.balance(Account::Dominion(0)) as f32;
        assert!((ledger_agg - w.total_dominion(0)).abs() < 0.05);
    }

    #[test]
    fn diffusion_conserves_and_spreads() {
        let (mut w, _l) = scenario::duel_line(6, 7);
        // Seed all of faction 0's mass in province 0.
        for p in w.provinces.iter_mut() {
            p.dom[0] = 0.0;
        }
        w.provinces[0].dom[0] = 100.0;
        let total_before = w.total_dominion(0);
        diffuse(&mut w);
        let total_after = w.total_dominion(0);
        assert!((total_before - total_after).abs() < 1e-2, "diffusion conserves mass");
        assert!(w.provinces[1].dom[0] > 0.0, "faith spread to a neighbor");
    }

    #[test]
    fn diffusion_ignores_height() {
        // Two identical chains except elevation differs; spread must be identical.
        let run = |elev: u8| {
            let (mut w, _l) = scenario::duel_line(4, 3);
            for p in w.provinces.iter_mut() {
                p.dom[0] = 0.0;
                p.elevation = elev;
            }
            w.provinces[0].dom[0] = 50.0;
            diffuse(&mut w);
            w.provinces[1].dom[0]
        };
        let low = run(5);
        let high = run(95);
        assert!((low - high).abs() < 1e-6, "elevation must not affect the tide");
    }

    #[test]
    fn cancellation_erodes_and_sinks() {
        let (mut w, mut l) = scenario::duel_line(3, 9);
        let mid = 1usize;
        w.provinces[mid].dom[0] = 20.0;
        w.provinces[mid].dom[1] = 15.0;
        let sum_before = w.provinces[mid].dom[0] + w.provinces[mid].dom[1];
        cancel_contested(&mut w, &mut l);
        let sum_after = w.provinces[mid].dom[0] + w.provinces[mid].dom[1];
        assert!(sum_after < sum_before, "contested faith erodes");
        // Destroyed mass is accounted in the sink; books balance.
        assert!(l.balance(Account::DominionSink) > 0.0);
        l.assert_balanced();
    }
}
