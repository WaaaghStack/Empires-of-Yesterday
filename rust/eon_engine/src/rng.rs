//! Deterministic, seedable PRNG (SplitMix64).
//!
//! Determinism is the engine's core contract (see `eoy-sim-transaction-engine`): the same
//! `initial state + seed + transaction order` must always fold to the same result. We use a
//! small, well-known, fixed algorithm with no external dependency so the stream never shifts
//! under us across toolchain or crate versions.

/// SplitMix64 generator. Cheap, stateless-to-construct, good enough for sim tie-breaks and
/// bounded jitter. Not cryptographic.
#[derive(Clone, Debug)]
pub struct Rng {
    state: u64,
}

impl Rng {
    /// Seed the generator. Any seed is valid.
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    /// Derive an independent sub-stream keyed by `(turn, phase, salt)`. Mixing the inputs keeps
    /// per-phase streams reproducible and decorrelated regardless of call order elsewhere.
    pub fn stream(base_seed: u64, turn: u32, phase: u16, salt: u64) -> Self {
        let mut z = base_seed
            ^ (turn as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
            ^ (phase as u64).wrapping_mul(0xD1B5_4A32_D192_ED03)
            ^ salt.wrapping_mul(0xCA5C_2A2D_2A25_9AF9);
        // Avalanche the composed seed once so nearby (turn,phase,salt) tuples diverge immediately.
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^= z >> 31;
        Self { state: z }
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform f32 in [0, 1).
    pub fn next_f32(&mut self) -> f32 {
        // Top 24 bits → mantissa precision for f32.
        ((self.next_u64() >> 40) as f32) / ((1u32 << 24) as f32)
    }

    /// Uniform integer in [0, n). Returns 0 when n == 0.
    pub fn below(&mut self, n: u32) -> u32 {
        if n == 0 {
            return 0;
        }
        (self.next_u64() % (n as u64)) as u32
    }

    /// True with probability `p` (clamped to [0,1]).
    pub fn chance(&mut self, p: f32) -> bool {
        self.next_f32() < p.clamp(0.0, 1.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_same_stream() {
        let mut a = Rng::new(42);
        let mut b = Rng::new(42);
        for _ in 0..1000 {
            assert_eq!(a.next_u64(), b.next_u64());
        }
    }

    #[test]
    fn different_seed_diverges() {
        let mut a = Rng::new(1);
        let mut b = Rng::new(2);
        let mut same = 0;
        for _ in 0..64 {
            if a.next_u64() == b.next_u64() {
                same += 1;
            }
        }
        assert!(same < 4, "streams should not track each other");
    }

    #[test]
    fn streams_are_reproducible_and_decorrelated() {
        let s1 = Rng::stream(7, 3, 5, 9).next_u64();
        let s1b = Rng::stream(7, 3, 5, 9).next_u64();
        let s2 = Rng::stream(7, 3, 5, 10).next_u64();
        assert_eq!(s1, s1b, "same key → same stream");
        assert_ne!(s1, s2, "adjacent salt → different stream");
    }

    #[test]
    fn f32_in_unit_interval() {
        let mut r = Rng::new(123);
        for _ in 0..10_000 {
            let v = r.next_f32();
            assert!((0.0..1.0).contains(&v));
        }
    }

    #[test]
    fn below_is_bounded() {
        let mut r = Rng::new(99);
        for _ in 0..10_000 {
            assert!(r.below(6) < 6);
        }
        assert_eq!(r.below(0), 0);
    }
}
