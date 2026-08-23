---
name: eoy-scd1-presentation
description: Guides Empires of Yesterday live paint via SCD1 versioned domain pulls (WorldDataset authority, apply-only Godot). Use for territory/structures/agents/bombers/wallet sync, desync, full-pull gaps, or PresentationTxn confusion.
---

# EOY SCD1 presentation

## Canon

- [DESIGN.md](../../../DESIGN.md) — WorldDataset + SCD1
- [docs/REQUEST_SCD1_VERSIONED_PULL.md](../../../docs/REQUEST_SCD1_VERSIONED_PULL.md)
- [RUST.md](../../../RUST.md) — `pull_domain_since`, domain epochs
- [PERFORMANCE.md](../../../PERFORMANCE.md) — paint budgets

## Live rules

1. **Rust** mutates sim truth (WorldDataset).
2. **Godot** pulls domains and applies — do not treat Godot as authority for owners/structures/units/wallet in live Play.
3. Use `pull_domain_since(domain, last_version, force_full)` / `Scd1DomainPull.gd`.
4. **PresentationTxn** (`pull_presentation_txn`) is **legacy/QA only** — not live paint.

## Domains (Godot live)

`territory`, `structures`, `agents`, `bombers`, `wallet`

Roads domain retired under **R1** (Rust may keep ABI; Godot should not pull it for Play).

## Change checklist

- [ ] Which domain(s) and row `version` fields?
- [ ] Incremental vs full pull / gap policy (`domain_version.rs`, `scd1_decide_full_pull`)
- [ ] Tombstones / `removed_ids` for structures if needed
- [ ] Harness: `scd1_version_pull_harness.gd`, `WorldDatasetAssert.gd`
- [ ] Rebuild DLL if Rust changed (`eoy-rust-gdextension`) then QA (`eoy-qa-lifecycle`)

## Anti-patterns

- Reintroducing PresentationTxn as the live path
- Full snaps every frame
- Mutating authoritative state only on the Godot side in live Play
