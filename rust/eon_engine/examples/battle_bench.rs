//! Measure battle scale + duration: resolve a large battle and report unit count, sim ticks,
//! recorded frames, and wall-clock resolve time. `cargo run --release --example battle_bench [per_side]`

use eon_engine::battle::resolve_battle_in_province;
use eon_engine::model::{Squad, UnitKind};
use eon_engine::scenario;
use std::time::Instant;

fn main() {
    let per_side: u32 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(260);
    let (mut w, mut l) = scenario::duel_line(3, 12345);
    let seed = w.seed;
    scenario::recruit_army(&mut w, &mut l, 0, 1, vec![
        Squad { kind: UnitKind::Soldier, count: per_side * 85 / 100 },
        Squad { kind: UnitKind::Bomber, count: per_side * 15 / 100 },
    ]);
    scenario::recruit_army(&mut w, &mut l, 1, 1, vec![
        Squad { kind: UnitKind::Soldier, count: per_side * 85 / 100 },
        Squad { kind: UnitKind::Bomber, count: per_side * 15 / 100 },
    ]);
    let t0 = Instant::now();
    let r = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, seed);
    let dt = t0.elapsed();
    let total: u32 = r.initial.iter().map(|(_, n)| *n).sum();
    println!(
        "units={} ticks={} frames={} resolve_ms={:.1} winner={:?} reconciles={}",
        total, r.ticks, r.frames.len(), dt.as_secs_f64() * 1000.0, r.winner, r.reconciles()
    );
}
