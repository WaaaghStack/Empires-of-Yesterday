//! SCD1 domain monotonic versions + gap-recovery policy (see docs/REQUEST_SCD1_VERSIONED_PULL.md).
//!
//! Per-domain epoch: on write, bump epoch and stamp rows with that version.
//! Godot pulls rows with version > last_seen. Full pull only at start / allow-listed gap.

use std::time::{Duration, Instant};

/// Domain ids match the request table (stable for FFI strings).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum DomainId {
    Territory = 0,
    Structures = 1,
    Roads = 2,
    Agents = 3,
    Bombers = 4,
    Wallet = 5,
}

pub const DOMAIN_COUNT: usize = 6;

impl DomainId {
    pub fn as_str(self) -> &'static str {
        match self {
            DomainId::Territory => "territory",
            DomainId::Structures => "structures",
            DomainId::Roads => "roads",
            DomainId::Agents => "agents",
            DomainId::Bombers => "bombers",
            DomainId::Wallet => "wallet",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "territory" | "grid" | "owners" => Some(DomainId::Territory),
            "structures" => Some(DomainId::Structures),
            "roads" | "logistics" => Some(DomainId::Roads),
            "agents" | "soldiers" => Some(DomainId::Agents),
            "bombers" => Some(DomainId::Bombers),
            "wallet" | "resources" => Some(DomainId::Wallet),
            _ => None,
        }
    }

    pub fn all() -> [DomainId; DOMAIN_COUNT] {
        [
            DomainId::Territory,
            DomainId::Structures,
            DomainId::Roads,
            DomainId::Agents,
            DomainId::Bombers,
            DomainId::Wallet,
        ]
    }

    pub fn index(self) -> usize {
        self as usize
    }
}

/// Per-domain high-water epochs (monotonic).
#[derive(Clone, Debug)]
pub struct DomainBook {
    epochs: [u64; DOMAIN_COUNT],
    /// Match / sim generation — bump on world rebuild so clients force seed.
    pub sim_generation: u64,
}

impl Default for DomainBook {
    fn default() -> Self {
        Self {
            epochs: [0; DOMAIN_COUNT],
            sim_generation: 1,
        }
    }
}

impl DomainBook {
    pub fn epoch(&self, d: DomainId) -> u64 {
        self.epochs[d.index()]
    }

    /// Bump domain epoch; return the new high-water (stamp rows with this).
    pub fn touch(&mut self, d: DomainId) -> u64 {
        let i = d.index();
        self.epochs[i] = self.epochs[i].saturating_add(1);
        self.epochs[i]
    }

    pub fn bump_sim_generation(&mut self) {
        self.sim_generation = self.sim_generation.saturating_add(1);
        // Reset domain epochs so last_version from prior match cannot silently incremental-sync.
        self.epochs = [0; DOMAIN_COUNT];
    }
}

/// Allow-listed reasons for full domain pull (Policy 2).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FullPullReason {
    Start,
    SimReset,
    HardError,
    SessionMismatch,
    ChecksumConsecutive,
}

impl FullPullReason {
    pub fn as_str(self) -> &'static str {
        match self {
            FullPullReason::Start => "start",
            FullPullReason::SimReset => "sim_reset",
            FullPullReason::HardError => "hard_error",
            FullPullReason::SessionMismatch => "session_mismatch",
            FullPullReason::ChecksumConsecutive => "checksum_consecutive",
        }
    }
}

/// Default cooldown between full pulls (Policy 3) — 3 seconds.
pub const FULL_PULL_COOLDOWN: Duration = Duration::from_secs(3);

/// Consecutive checksum failures before optional full pull (Policy 2 optional path).
pub const CHECKSUM_FAILS_BEFORE_FULL: u32 = 3;

/// Pure decision: should this pull be full? (Policies 1, 2, 5 — no MAX_GAP force-full.)
pub fn decide_full_pull(
    last_version: u64,
    high_water: u64,
    client_sim_gen: u64,
    server_sim_gen: u64,
    hard_error: bool,
) -> Option<FullPullReason> {
    if hard_error {
        return Some(FullPullReason::HardError);
    }
    if client_sim_gen != server_sim_gen {
        return Some(FullPullReason::SimReset);
    }
    if last_version == 0 {
        return Some(FullPullReason::Start);
    }
    // Session mismatch: client ahead of server (wrong instance / reset).
    if last_version > high_water {
        return Some(FullPullReason::SessionMismatch);
    }
    // Policy 5: last < high_water → incremental catch-up, NOT full.
    None
}

/// Circuit breaker: deny full pull if last full was too recent (Policy 3).
pub fn full_pull_allowed_by_cooldown(last_full: Option<Instant>, now: Instant) -> bool {
    match last_full {
        None => true,
        Some(t) => now.duration_since(t) >= FULL_PULL_COOLDOWN,
    }
}

/// Filter ids whose version is strictly greater than last (incremental SCD1).
pub fn filter_ids_since(versions: &[(i32, u64)], last: u64) -> Vec<i32> {
    versions
        .iter()
        .filter(|(_, v)| *v > last)
        .map(|(id, _)| *id)
        .collect()
}

/// Empty incremental when client is caught up.
pub fn is_caught_up(last: u64, high_water: u64) -> bool {
    last >= high_water && last > 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn touch_bumps_epoch_monotonically() {
        let mut book = DomainBook::default();
        assert_eq!(book.epoch(DomainId::Structures), 0);
        let v1 = book.touch(DomainId::Structures);
        let v2 = book.touch(DomainId::Structures);
        assert_eq!(v1, 1);
        assert_eq!(v2, 2);
        assert_eq!(book.epoch(DomainId::Agents), 0);
    }

    #[test]
    fn decide_full_only_allow_list() {
        assert_eq!(
            decide_full_pull(0, 0, 1, 1, false),
            Some(FullPullReason::Start)
        );
        assert_eq!(
            decide_full_pull(5, 10, 1, 1, false),
            None,
            "behind is incremental catch-up, not full"
        );
        assert_eq!(
            decide_full_pull(10, 10, 1, 1, false),
            None,
            "caught up — no full"
        );
        assert_eq!(
            decide_full_pull(99, 10, 1, 1, false),
            Some(FullPullReason::SessionMismatch)
        );
        assert_eq!(
            decide_full_pull(5, 10, 1, 2, false),
            Some(FullPullReason::SimReset)
        );
        assert_eq!(
            decide_full_pull(5, 10, 1, 1, true),
            Some(FullPullReason::HardError)
        );
    }

    #[test]
    fn busy_behind_is_not_full() {
        // Many versions advanced — still None (Policy 5).
        assert_eq!(decide_full_pull(1, 50_000, 1, 1, false), None);
    }

    #[test]
    fn cooldown_blocks_repeat_full() {
        let t0 = Instant::now();
        assert!(full_pull_allowed_by_cooldown(None, t0));
        assert!(!full_pull_allowed_by_cooldown(Some(t0), t0));
        assert!(full_pull_allowed_by_cooldown(
            Some(t0),
            t0 + FULL_PULL_COOLDOWN + Duration::from_millis(1)
        ));
    }

    #[test]
    fn filter_ids_since_only_newer() {
        let v = vec![(1, 3), (2, 5), (3, 5), (4, 1)];
        assert_eq!(filter_ids_since(&v, 3), vec![2, 3]);
        assert!(filter_ids_since(&v, 5).is_empty());
    }

    #[test]
    fn domain_from_str() {
        assert_eq!(DomainId::from_str("structures"), Some(DomainId::Structures));
        assert_eq!(DomainId::from_str("roads"), Some(DomainId::Roads));
        assert_eq!(DomainId::from_str("nope"), None);
    }

    #[test]
    fn sim_generation_resets_epochs() {
        let mut book = DomainBook::default();
        book.touch(DomainId::Structures);
        book.bump_sim_generation();
        assert_eq!(book.sim_generation, 2);
        assert_eq!(book.epoch(DomainId::Structures), 0);
    }
}
