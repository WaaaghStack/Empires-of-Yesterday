//! The transaction ledger — the authority's append-only journal.
//!
//! Implements the accounting model from `eoy-sim-transaction-engine`:
//! - **Append-only journal**: transactions are posted, never edited/deleted. Corrections are
//!   reversing transactions.
//! - **Double-entry**: every transaction's postings sum to zero, so the books always balance
//!   (`trial_balance() == 0`). Creation/destruction is explicit via source/sink accounts.
//! - **One-way reporting**: wide-row reports are projected from state and must *reconcile* with
//!   the ledger aggregates (see `crate::turn::TurnReport::reconcile`).

use crate::model::{FactionId, GemPath};

/// A tracked quantity. All conserved sim quantities are ledger accounts so the books balance.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Account {
    /// Total dominion mass currently held across provinces by a faction.
    Dominion(FactionId),
    /// Source (credit) account for injected dominion (temples/prophets/capital). Balance trends
    /// negative — it is where minted dominion is drawn from so the books net to zero.
    DominionSource(FactionId),
    /// Sink for dominion destroyed by mutual cancellation.
    DominionSink,
    /// Living units owned by a faction (campaign roster).
    UnitsAlive(FactionId),
    /// Source (credit) account for recruited units so seeding the roster stays double-entry.
    UnitSource(FactionId),
    /// Cumulative battle casualties for a faction (alive → casualties is a conserving transfer).
    Casualties(FactionId),
    /// Magic gems held by a faction on a path.
    Gems(FactionId, GemPath),
    /// Source (credit) account for minted gems from owned deposits.
    GemSource(FactionId),
}

/// Which ordered phase posted a transaction (Dominions-style order of operations).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Income,
    Upkeep,
    Agents,
    Rituals,
    Movement,
    Battles,
    Dominion,
    Corruption,
    Events,
    WinCheck,
}

impl Phase {
    pub fn as_str(self) -> &'static str {
        match self {
            Phase::Income => "income",
            Phase::Upkeep => "upkeep",
            Phase::Agents => "agents",
            Phase::Rituals => "rituals",
            Phase::Movement => "movement",
            Phase::Battles => "battles",
            Phase::Dominion => "dominion",
            Phase::Corruption => "corruption",
            Phase::Events => "events",
            Phase::WinCheck => "win_check",
        }
    }

    /// Stable phase index used to key deterministic per-phase RNG streams.
    pub fn stream_key(self) -> u16 {
        self as u16
    }
}

/// One posted journal entry. Immutable once appended.
#[derive(Clone, Debug)]
pub struct Txn {
    pub seq: u64,
    pub turn: u32,
    pub phase: Phase,
    /// Stable operation tag (audit-friendly, e.g. "inject_dominion", "cancel", "casualties").
    pub kind: &'static str,
    /// Double-entry postings; must sum to ~0.
    pub postings: Vec<(Account, f64)>,
    /// Human note for drill-down (e.g. province/faction ids).
    pub note: String,
}

/// Postings whose absolute sum is below this are treated as balanced (float slack).
const BALANCE_EPS: f64 = 1e-6;

/// Append-only journal + running balances.
#[derive(Clone, Debug, Default)]
pub struct Ledger {
    seq: u64,
    journal: Vec<Txn>,
    balances: std::collections::BTreeMap<Account, f64>,
}

impl Ledger {
    pub fn new() -> Self {
        Self::default()
    }

    /// Post a balanced transaction. Panics in debug if postings do not net to zero — an
    /// unbalanced post is a programming error (silent creation/destruction of a tracked quantity).
    pub fn post(
        &mut self,
        turn: u32,
        phase: Phase,
        kind: &'static str,
        postings: Vec<(Account, f64)>,
        note: impl Into<String>,
    ) -> u64 {
        let sum: f64 = postings.iter().map(|(_, d)| *d).sum();
        debug_assert!(
            sum.abs() < BALANCE_EPS,
            "unbalanced posting for '{kind}' (sum={sum}); postings must be double-entry"
        );
        for (acc, delta) in &postings {
            *self.balances.entry(*acc).or_insert(0.0) += *delta;
        }
        self.seq += 1;
        let seq = self.seq;
        self.journal.push(Txn {
            seq,
            turn,
            phase,
            kind,
            postings,
            note: note.into(),
        });
        seq
    }

    pub fn balance(&self, acc: Account) -> f64 {
        self.balances.get(&acc).copied().unwrap_or(0.0)
    }

    /// Sum of every account balance. Must always be ~0 (double-entry invariant).
    pub fn trial_balance(&self) -> f64 {
        self.balances.values().sum()
    }

    /// Assert the books balance. Cheap; call at phase boundaries.
    pub fn assert_balanced(&self) {
        let tb = self.trial_balance();
        debug_assert!(tb.abs() < 1e-3, "ledger does not balance: trial_balance={tb}");
    }

    pub fn journal(&self) -> &[Txn] {
        &self.journal
    }

    pub fn len(&self) -> usize {
        self.journal.len()
    }

    pub fn is_empty(&self) -> bool {
        self.journal.is_empty()
    }

    /// Order-independent digest of the whole journal — used to prove replay determinism.
    pub fn digest(&self) -> u64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325; // FNV-1a offset basis
        let mix = |x: u64, h: &mut u64| {
            *h ^= x;
            *h = h.wrapping_mul(0x0000_0100_0000_01B3);
        };
        for t in &self.journal {
            mix(t.seq, &mut h);
            mix(t.turn as u64, &mut h);
            mix(t.phase as u64, &mut h);
            for b in t.kind.bytes() {
                mix(b as u64, &mut h);
            }
            for (acc, d) in &t.postings {
                mix(account_key(*acc), &mut h);
                // Quantize the float so tiny FP noise does not change the digest.
                mix((d * 1000.0).round() as i64 as u64, &mut h);
            }
        }
        h
    }
}

/// Stable integer key for an account (digest + deterministic ordering helper).
fn account_key(acc: Account) -> u64 {
    match acc {
        Account::Dominion(f) => 0x01_0000_0000 | f as u64,
        Account::DominionSource(f) => 0x02_0000_0000 | f as u64,
        Account::DominionSink => 0x03_0000_0000,
        Account::UnitsAlive(f) => 0x04_0000_0000 | f as u64,
        Account::Casualties(f) => 0x05_0000_0000 | f as u64,
        Account::Gems(f, p) => 0x06_0000_0000 | ((p as u64) << 16) | f as u64,
        Account::GemSource(f) => 0x07_0000_0000 | f as u64,
        Account::UnitSource(f) => 0x08_0000_0000 | f as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn balanced_post_keeps_books_at_zero() {
        let mut l = Ledger::new();
        // Mint 100 dominion for faction 0: +Dominion, -DominionSource (nets zero).
        l.post(
            1,
            Phase::Dominion,
            "inject_dominion",
            vec![(Account::Dominion(0), 100.0), (Account::DominionSource(0), -100.0)],
            "cap",
        );
        assert!((l.balance(Account::Dominion(0)) - 100.0).abs() < 1e-9);
        assert!(l.trial_balance().abs() < 1e-9);
        l.assert_balanced();
    }

    #[test]
    fn casualties_conserve_units() {
        let mut l = Ledger::new();
        l.post(
            1,
            Phase::Income,
            "recruit",
            vec![(Account::UnitsAlive(0), 10.0), (Account::DominionSource(0), -10.0)],
            "seed roster",
        );
        // Kill 3: alive → casualties (conserving transfer).
        l.post(
            2,
            Phase::Battles,
            "casualties",
            vec![(Account::UnitsAlive(0), -3.0), (Account::Casualties(0), 3.0)],
            "battle 1",
        );
        assert_eq!(l.balance(Account::UnitsAlive(0)), 7.0);
        assert_eq!(l.balance(Account::Casualties(0)), 3.0);
        // alive + casualties == original recruited
        assert_eq!(
            l.balance(Account::UnitsAlive(0)) + l.balance(Account::Casualties(0)),
            10.0
        );
        l.assert_balanced();
    }

    #[test]
    fn reversing_entry_undoes_without_editing_history() {
        let mut l = Ledger::new();
        l.post(
            1,
            Phase::Rituals,
            "spend_gems",
            vec![(Account::Gems(0, GemPath::Aurelium), -5.0), (Account::GemSource(0), 5.0)],
            "ritual",
        );
        let before = l.len();
        // Correct a mistaken spend by posting the reverse — history is preserved.
        l.post(
            1,
            Phase::Rituals,
            "reverse_spend_gems",
            vec![(Account::Gems(0, GemPath::Aurelium), 5.0), (Account::GemSource(0), -5.0)],
            "reversal",
        );
        assert_eq!(l.balance(Account::Gems(0, GemPath::Aurelium)), 0.0);
        assert_eq!(l.len(), before + 1, "reversal appends, never edits");
    }

    #[test]
    fn digest_is_stable_and_sensitive() {
        let build = || {
            let mut l = Ledger::new();
            l.post(
                1,
                Phase::Dominion,
                "inject_dominion",
                vec![(Account::Dominion(0), 10.0), (Account::DominionSource(0), -10.0)],
                "a",
            );
            l
        };
        assert_eq!(build().digest(), build().digest());
        let mut other = build();
        other.post(
            1,
            Phase::Dominion,
            "inject_dominion",
            vec![(Account::Dominion(1), 1.0), (Account::DominionSource(1), -1.0)],
            "b",
        );
        assert_ne!(build().digest(), other.digest());
    }
}
