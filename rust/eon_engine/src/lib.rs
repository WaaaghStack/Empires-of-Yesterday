//! # eon_engine — Empires of Yesterday two-worlds transaction engine
//!
//! Godot-agnostic, deterministic authority for the proposed turn-based reframe
//! (see `docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md` and the `eoy-sim-transaction-engine` /
//! `eoy-battle-resolve` skills). Two worlds — the **World** (campaign) and a **Battle** — share
//! one pattern: an ordered **transaction ledger** (authority, narrow tables) projected to a
//! **wide-row report** (presentation/replay). Determinism is a hard contract.
//!
//! This crate is intentionally free of any Godot dependency so it is fast and trivial to unit
//! test; the `empire_territory` GDExtension wraps it for in-engine use.

pub mod agents;
pub mod battle;
pub mod dominion;
pub mod ledger;
pub mod model;
pub mod rng;
pub mod scenario;
pub mod turn;

pub use ledger::{Account, Ledger, Phase};
pub use model::{Config, World};
pub use turn::{run_turn, Outcome, TurnReport, VictoryKind};

/// Run a headless demo campaign and return a compact, human-readable wide-row report string.
/// Used by the GDExtension self-check and as living documentation of the engine end-to-end.
pub fn run_headless_demo(seed: u64, turns: u32) -> String {
    let (mut world, mut ledger) = scenario::demo_world(seed);
    let mut battles_total = 0usize;
    let mut last: Option<TurnReport> = None;
    let mut outcome = Outcome::Ongoing;
    for _ in 0..turns {
        let report = run_turn(&mut world, &mut ledger);
        battles_total += report.battles.len();
        outcome = report.outcome;
        let reconciled = report.reconcile(&world, &ledger);
        last = Some(report);
        if !reconciled {
            return format!("RECONCILE FAILURE at turn {}", world.turn);
        }
        if !matches!(outcome, Outcome::Ongoing) {
            break;
        }
    }

    let mut out = String::new();
    out.push_str(&format!(
        "=== eon_engine demo — seed {seed}, {} turns, {} battles ===\n",
        world.turn, battles_total
    ));
    if let Some(r) = &last {
        for fr in &r.factions {
            out.push_str(&format!(
                "F{} {:<8} dominion={:>7.1} land={:>2} units={:>3} thrones={} alive={}\n",
                fr.faction,
                world.factions[fr.faction as usize].name,
                fr.total_dominion,
                fr.owned_land,
                fr.units_alive,
                fr.ascension,
                fr.alive,
            ));
        }
    }
    out.push_str(&format!(
        "ledger: {} txns, trial_balance={:.4}, journal_digest={:#018x}\n",
        ledger.len(),
        ledger.trial_balance(),
        ledger.digest()
    ));
    out.push_str(&format!("outcome: {:?}\n", outcome));
    out
}

#[cfg(test)]
mod integration {
    use super::*;

    #[test]
    fn headless_demo_reconciles_and_is_deterministic() {
        let a = run_headless_demo(2026, 40);
        let b = run_headless_demo(2026, 40);
        assert_eq!(a, b, "headless demo must be fully deterministic");
        assert!(!a.contains("RECONCILE FAILURE"), "every turn must reconcile:\n{a}");
        assert!(a.contains("journal_digest="));
    }

    #[test]
    fn two_worlds_share_the_ledger_contract() {
        // A world turn that triggers a battle: the battle's casualties are posted back into the
        // same World ledger, and the trial balance still nets to zero.
        let (mut w, mut l) = scenario::demo_world(55);
        let mut saw_battle = false;
        for _ in 0..30 {
            let r = run_turn(&mut w, &mut l);
            if !r.battles.is_empty() {
                saw_battle = true;
                assert!(r.battles.iter().all(|b| b.reconciles()));
            }
            assert!(l.trial_balance().abs() < 1e-3, "books must balance every turn");
            if !matches!(r.outcome, Outcome::Ongoing) {
                break;
            }
        }
        assert!(saw_battle, "the demo campaign should produce at least one battle");
    }
}
