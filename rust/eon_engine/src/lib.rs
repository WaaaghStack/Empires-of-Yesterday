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

/// Result of one AI-vs-AI campaign (both factions driven by the built-in AI).
#[derive(Clone, Copy, Debug)]
pub struct AiMatchResult {
    pub seed: u64,
    pub turns: u32,
    pub outcome: Outcome,
    pub reconciled: bool,
    pub battles: u32,
}

/// Run one fully-autonomous AI-vs-AI campaign to a decisive outcome (or `max_turns`).
pub fn run_ai_vs_ai(seed: u64, max_turns: u32) -> AiMatchResult {
    let (mut world, mut ledger) = scenario::procedural_world(seed);
    let mut outcome = Outcome::Ongoing;
    let mut reconciled = true;
    let mut battles = 0u32;
    for _ in 0..max_turns {
        let r = run_turn(&mut world, &mut ledger);
        battles += r.battles.len() as u32;
        if !r.reconcile(&world, &ledger) {
            reconciled = false;
        }
        outcome = r.outcome;
        if !matches!(outcome, Outcome::Ongoing) {
            break;
        }
    }
    AiMatchResult { seed, turns: world.turn, outcome, reconciled, battles }
}

/// Run a batch of AI-vs-AI campaigns and return a human-readable validation report: winner
/// distribution, decisiveness, reconciliation, and determinism. Used by tests and the in-engine
/// self-check to confirm AI-vs-AI works as expected on the new setup.
pub fn run_ai_vs_ai_batch(count: u32, max_turns: u32) -> String {
    let mut wins = [0u32; 2];
    let mut ascension = 0u32;
    let mut conquest = 0u32;
    let mut dominion_kill = 0u32;
    let mut score = 0u32;
    let mut ongoing = 0u32;
    let mut battles_total = 0u32;
    let mut all_reconciled = true;
    let mut turns_sum = 0u32;

    for s in 0..count as u64 {
        let r = run_ai_vs_ai(s, max_turns);
        battles_total += r.battles;
        turns_sum += r.turns;
        if !r.reconciled {
            all_reconciled = false;
        }
        match r.outcome {
            Outcome::Victory(f, kind) => {
                if (f as usize) < 2 {
                    wins[f as usize] += 1;
                }
                match kind {
                    VictoryKind::Ascension => ascension += 1,
                    VictoryKind::Conquest => conquest += 1,
                    VictoryKind::DominionKill => dominion_kill += 1,
                    VictoryKind::Score => score += 1,
                }
            }
            Outcome::Ongoing => ongoing += 1,
        }
    }

    // Determinism: a couple of seeds must reproduce exactly.
    let deterministic = (0..3u64).all(|s| {
        let a = run_ai_vs_ai(s, max_turns);
        let b = run_ai_vs_ai(s, max_turns);
        a.turns == b.turns && format!("{:?}", a.outcome) == format!("{:?}", b.outcome)
    });

    format!(
        "AI-vs-AI batch: {count} matches, max_turns={max_turns}\n\
         wins: F0={} F1={} | undecided={ongoing}\n\
         by kind: ascension={ascension} conquest={conquest} dominion_kill={dominion_kill} score={score}\n\
         battles_total={battles_total} avg_turns={:.1}\n\
         all_reconciled={all_reconciled} deterministic={deterministic}\n",
        wins[0],
        wins[1],
        turns_sum as f32 / count.max(1) as f32,
    )
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
    fn ai_vs_ai_campaigns_resolve_reconcile_and_vary() {
        let report = run_ai_vs_ai_batch(24, 400);
        println!("{report}");
        assert!(report.contains("all_reconciled=true"), "every AI-vs-AI turn must reconcile:\n{report}");
        assert!(report.contains("deterministic=true"), "AI-vs-AI must be deterministic:\n{report}");
        // Most matches should reach a decision; a rare stalemate (each side holding one of two
        // thrones with stable fronts) is a legitimate outcome, so allow a small number.
        let undecided = parse_kv(&report, "undecided=");
        assert!(undecided <= 3, "too many undecided AI-vs-AI matches ({undecided}/24):\n{report}");
        // Both factions must win some seeds — proves the AI genuinely contests and the outcome is
        // not structurally rigged toward one side.
        let f0 = parse_kv(&report, "F0=");
        let f1 = parse_kv(&report, "F1=");
        assert!(f0 >= 1 && f1 >= 1, "both factions should win some seeds (F0={f0}, F1={f1}):\n{report}");
    }

    fn parse_kv(report: &str, key: &str) -> u32 {
        report
            .split_whitespace()
            .find_map(|tok| tok.strip_prefix(key))
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
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
