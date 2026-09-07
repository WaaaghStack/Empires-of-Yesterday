---
name: eoy-sim-transaction-engine
description: Empires of Yesterday proposed turn-based authority as an ordered transaction engine (Dominions-style order-of-operations) over narrow tables, with wide rows only in the presentation/replay layer. Use when designing/implementing the two-worlds (World + Battle) sim spine, turn resolution, determinism, or the narrow-vs-wide contract.
---

# EOY sim transaction engine (proposed)

> **Status: exploratory proposal.** Not built, not accepted. The turn-based reframe and its
> design-lock changes require `product-manager` signoff + a `DESIGN.md` edit first
> (`eoy-design-lock-change`). Do not treat this as shipped behavior.

## Canon

- [docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md](../../../docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md) — full design
- [DESIGN.md](../../../DESIGN.md) — WorldDataset authority, design locks
- [RUST.md](../../../RUST.md) — authority modules, domain epochs
- Companion skills: `eoy-battle-resolve`, `eoy-scd1-presentation`

## The spine: two worlds, one engine

Two worlds — **the World (globe/campaign)** and **a Battle** — are the **same three layers**:

1. **Authority (narrow):** an ordered **transaction engine** over normalized tables. World resolves
   **per turn**; Battle resolves **per tick**.
2. **Transaction log:** the ordered record of what happened — the **source of truth** and the
   **canonical replay**.
3. **Presentation (wide rows):** SCD1 domain pulls / EYTR frames / RGBA bakes — **projections only**
   that the user watches (globe turn playback; HD-2D battle replay).

## Hard rules

1. **Ordered transactions.** Resolve as a strict sequence: txn reads state → computes result →
   mutates → next txn runs against updated state. This is the Dominions **order-of-operations**.
2. **Determinism.** Fixed phase order; deterministic intra-phase ordering (by id / initiative); one
   **seeded PRNG** threaded through transactions; **single authority (Rust)**.
   `initial state + seed + txn order → identical result`.
3. **Narrow does the hard work.** Entity logic (units, squads, agents, commanders, rituals,
   provinces, structures, wallets) lives in transactions over **narrow/normalized tables**.
4. **Wide rows are presentation/replay only.** Never read denormalized/wide rows back into sim logic.
   The transaction log is the canonical replay; wide EYTR frames are an optional render cache.
5. **Fields run as a scheduled phase.** The Dominion field is a grid **stencil kernel** (array math),
   invoked as **one phase** in the order of operations — not millions of per-tile transactions. The
   pipeline stays one deterministic ordered sequence; the field math is internal to its phase.
6. **Battles nest under the World.** A `ResolveBattle(province)` world transaction spawns the battle
   sub-sim (own log + baked replay) and emits a **result transaction** back to the world log. Seeds
   thread World → Battle so the whole turn is reproducible from the world log.

## Not this

- **Not** `presentation_txn.rs` — that is a legacy QA-only *presentation* change feed, not the
  authority engine.
- **Not** a wide-array real-time sim doing entity logic every frame (that is today's live path).

## Change checklist

- [ ] New/edited transaction type(s): inputs, tables touched, ordering key?
- [ ] Correct phase + position in the order of operations?
- [ ] Seeded-PRNG threaded (no ambient randomness)? Deterministic iteration order?
- [ ] Field change → is it inside the scheduled field phase (stencil), not per-entity txns?
- [ ] Presentation/replay updated as a projection only (no read-back into sim)?
- [ ] Battle result surfaced back to the World log via a result transaction?
- [ ] Design-lock impact (turn-based, effective_height, F5, F6)? → `eoy-design-lock-change`.
- [ ] Rebuild DLL (`eoy-rust-gdextension`) + QA (`eoy-qa-lifecycle`) with deterministic goldens.

## Anti-patterns

- Wide/denormalized rows driving entity decisions.
- Ambient/unseeded RNG or order-dependent-but-unordered iteration (breaks replay).
- Turning the field into per-tile transactions.
- A second (GDScript) battle authority to keep in parity — resolve battles in Rust only.
- Editing `DESIGN.md` locks without PM signoff.
