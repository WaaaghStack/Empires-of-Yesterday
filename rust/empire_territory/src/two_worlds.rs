//! GDExtension surface for the proposed two-worlds transaction engine (`eon_engine`).
//!
//! This is the thin Godot wrapper over the godot-agnostic authority core. It lets Godot drive a
//! headless campaign and read back the wide-row report string. The heavy lifting (ordered
//! transactions, dominion field, deterministic battle resolve) lives in `eon_engine` and is
//! unit-tested there; this class only marshals to/from Godot types.
//!
//! Status: exploratory MVP (see docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md). It does not touch
//! the live World Conquest path — it is an additive, opt-in class.

use eon_engine::{run_ai_vs_ai_batch, run_headless_demo, scenario, turn::run_turn, Outcome};
use godot::prelude::*;

/// RefCounted entry point for the two-worlds engine. Reachable from GDScript as `TwoWorldsEngine`.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct TwoWorldsEngine {
    base: Base<RefCounted>,
}

#[godot_api]
impl TwoWorldsEngine {
    /// Run a headless demo campaign and return the wide-row report as text.
    #[func]
    fn run_demo(&self, seed: i64, turns: i64) -> GString {
        let report = run_headless_demo(seed as u64, turns.max(0) as u32);
        GString::from(report.as_str())
    }

    /// Self-check: prove determinism + per-turn reconciliation. Returns a one-line verdict plus
    /// the report, so a Godot smoke test can assert on it.
    #[func]
    fn self_check(&self) -> GString {
        let a = run_headless_demo(1234, 30);
        let b = run_headless_demo(1234, 30);
        let deterministic = a == b;
        let reconciled = !a.contains("RECONCILE FAILURE");
        let text = format!(
            "two_worlds self_check: deterministic={deterministic} reconciled={reconciled}\n{a}"
        );
        GString::from(text.as_str())
    }

    /// Run `count` fully-autonomous AI-vs-AI campaigns (both factions AI-driven) and return a
    /// validation report: winner distribution, decisiveness, reconciliation, and determinism.
    #[func]
    fn run_ai_vs_ai_batch(&self, count: i64, max_turns: i64) -> GString {
        let report = run_ai_vs_ai_batch(count.max(0) as u32, max_turns.max(1) as u32);
        GString::from(report.as_str())
    }

    /// Run `turns` and return a compact one-line-per-faction final summary as text.
    #[func]
    fn run_campaign_summary(&self, seed: i64, turns: i64) -> GString {
        let (mut world, mut ledger) = scenario::demo_world(seed as u64);
        let mut outcome = Outcome::Ongoing;
        let mut last = None;
        for _ in 0..turns.max(0) {
            let r = run_turn(&mut world, &mut ledger);
            outcome = r.outcome;
            last = Some(r);
            if !matches!(outcome, Outcome::Ongoing) {
                break;
            }
        }
        let mut text = format!(
            "turn={} txns={} trial_balance={:.4} outcome={:?}\n",
            world.turn,
            ledger.len(),
            ledger.trial_balance(),
            outcome
        );
        if let Some(r) = last {
            for fr in &r.factions {
                text.push_str(&format!(
                    "F{} dominion={:.1} land={} units={} thrones={} alive={}\n",
                    fr.faction,
                    fr.total_dominion,
                    fr.owned_land,
                    fr.units_alive,
                    fr.ascension,
                    fr.alive
                ));
            }
        }
        GString::from(text.as_str())
    }
}
