//! Agent phase — the Total-War-style meta verbs.
//!
//! Runs before the Dominion phase in the order of operations, so a prophet/priest that moves this
//! turn amplifies from its new province. All effects that touch a conserved quantity (spy sapping
//! enemy faith) are posted to the ledger; agent life/relations/reveal are entity state.

use crate::ledger::{Account, Ledger, Phase};
use crate::model::{AgentKind, FactionId, World};
use crate::rng::Rng;

pub fn agents_phase(world: &mut World, ledger: &mut Ledger, base_seed: u64) {
    move_agents(world);
    resolve_actions(world, ledger, base_seed);
    ledger.assert_balanced();
}

/// One-step movement to an adjacent province (limited campaign mobility).
fn move_agents(world: &mut World) {
    for i in 0..world.agents.len() {
        if !world.agents[i].alive {
            continue;
        }
        if let Some(dst) = world.agents[i].move_to.take() {
            let cur = world.agents[i].province;
            let adjacent = world.provinces[cur as usize].neighbors.contains(&dst);
            if adjacent && world.provinces[dst as usize].is_land {
                world.agents[i].province = dst;
            }
        }
    }
}

fn resolve_actions(world: &mut World, ledger: &mut Ledger, base_seed: u64) {
    let cfg = world.cfg.clone();
    let turn = world.turn;
    let fc = world.faction_count();

    for i in 0..world.agents.len() {
        let (alive, kind, faction, agent_id, target, prov) = {
            let a = &world.agents[i];
            (a.alive, a.kind, a.faction, a.id, a.target.unwrap_or(a.province), a.province)
        };
        if !alive {
            continue;
        }
        match kind {
            // Amplifiers act in the Dominion phase from their location; nothing to do here.
            AgentKind::Prophet | AgentKind::Priest => {}
            AgentKind::Spy => {
                // Sap the strongest enemy faith in the target province + raise unrest.
                let pid = target as usize;
                if !world.provinces[pid].is_land {
                    continue;
                }
                let mut victim: Option<FactionId> = None;
                let mut vval = 0.0f32;
                for f in 0..fc {
                    if f as FactionId == faction {
                        continue;
                    }
                    let d = world.provinces[pid].dom[f];
                    if d > vval {
                        vval = d;
                        victim = Some(f as FactionId);
                    }
                }
                if let Some(v) = victim {
                    let sap = cfg.spy_sap.min(world.provinces[pid].dom[v as usize]);
                    if sap > 0.0 {
                        world.provinces[pid].dom[v as usize] -= sap;
                        world.provinces[pid].unrest += cfg.spy_unrest;
                        ledger.post(
                            turn,
                            Phase::Agents,
                            "spy_sap",
                            vec![
                                (Account::Dominion(v), -(sap as f64)),
                                (Account::DominionSink, sap as f64),
                            ],
                            format!("spy f{faction} vs f{v} @prov{pid}"),
                        );
                    }
                }
            }
            AgentKind::Assassin => {
                let mut rng = Rng::stream(base_seed, turn, Phase::Agents.stream_key(), agent_id as u64);
                let chance = (cfg.assassin_base_chance + 0.1 * world.agents[i].level as f32).min(0.95);
                // First alive enemy agent in the target province (sorted by id → deterministic).
                let mut victims: Vec<usize> = (0..world.agents.len())
                    .filter(|&j| {
                        let a = &world.agents[j];
                        a.alive && a.faction != faction && a.province == target
                    })
                    .collect();
                victims.sort_by_key(|&j| world.agents[j].id);
                if let Some(&j) = victims.first() {
                    if rng.chance(chance) {
                        world.agents[j].alive = false;
                    }
                }
            }
            AgentKind::Diplomat => {
                // Warm relations between the diplomat's faction and the target province owner.
                if let Some(o) = world.provinces[target as usize].owner(&cfg) {
                    if o != faction {
                        let a = faction as usize;
                        let b = o as usize;
                        world.relations[a][b] = (world.relations[a][b] + 10).clamp(-100, 100);
                        world.relations[b][a] = world.relations[a][b];
                    }
                }
            }
            AgentKind::Scout => {
                world.provinces[target as usize].revealed = true;
            }
        }
        let _ = prov;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::AgentKind;
    use crate::scenario;

    #[test]
    fn spy_saps_enemy_faith_and_reconciles() {
        let (mut w, mut l) = scenario::duel_line(3, 5);
        let pid = 1usize;
        w.provinces[pid].dom[1] = 20.0; // enemy faith
        // Faction 0 spy targeting province 1.
        let aid = w.next_agent_id;
        w.next_agent_id += 1;
        w.agents.push(crate::model::Agent {
            id: aid,
            faction: 0,
            province: pid as u32,
            kind: AgentKind::Spy,
            level: 1,
            alive: true,
            target: Some(pid as u32),
            move_to: None,
        });
        let before = w.provinces[pid].dom[1];
        let seed = w.seed;
        agents_phase(&mut w, &mut l, seed);
        assert!(w.provinces[pid].dom[1] < before, "spy saps enemy faith");
        assert!(w.provinces[pid].unrest > 0.0, "spy raises unrest");
        assert!(l.balance(Account::DominionSink) > 0.0);
        l.assert_balanced();
    }

    #[test]
    fn assassin_is_deterministic() {
        let build = || {
            let (mut w, l) = scenario::duel_line(2, 77);
            let victim = w.next_agent_id;
            w.next_agent_id += 1;
            w.agents.push(crate::model::Agent {
                id: victim,
                faction: 1,
                province: 0,
                kind: AgentKind::Spy,
                level: 0,
                alive: true,
                target: None,
                move_to: None,
            });
            let killer = w.next_agent_id;
            w.next_agent_id += 1;
            w.agents.push(crate::model::Agent {
                id: killer,
                faction: 0,
                province: 0,
                kind: AgentKind::Assassin,
                level: 5,
                alive: true,
                target: Some(0),
                move_to: None,
            });
            (w, l)
        };
        let (mut w1, mut l1) = build();
        let (mut w2, mut l2) = build();
        let (s1, s2) = (w1.seed, w2.seed);
        agents_phase(&mut w1, &mut l1, s1);
        agents_phase(&mut w2, &mut l2, s2);
        let dead1: Vec<bool> = w1.agents.iter().map(|a| a.alive).collect();
        let dead2: Vec<bool> = w2.agents.iter().map(|a| a.alive).collect();
        assert_eq!(dead1, dead2, "assassination must be deterministic for a fixed seed");
    }
}
