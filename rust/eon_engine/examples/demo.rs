//! Headless demo run — prints the wide-row report for a full campaign.
//! `cargo run --example demo`

fn main() {
    let turns: u32 = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(60);
    let seed: u64 = std::env::args()
        .nth(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(2026);
    print!("{}", eon_engine::run_headless_demo(seed, turns));
}
