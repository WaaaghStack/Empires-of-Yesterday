---
name: eoy-rust-gdextension
description: Builds and installs the Empires of Yesterday empire_territory GDExtension (TerritorySim / WorldDataset). Use when rust/empire_territory/src changes, DLL mismatches Godot, or Rust vs CPU parity fails.
---

# EOY Rust GDExtension

Canon: [RUST.md](../../../RUST.md)

## When to rebuild

Any change under `rust/empire_territory/src/` (or economy tables mirrored into Rust) before playtest/QA that needs the new native code.

## Build

From repo root:

```powershell
.\setup_rust.ps1
```

Or:

```powershell
cd rust\empire_territory
cargo build --release
```

`setup_rust.ps1` builds and copies DLLs into `rust/empire_territory/bin/` with names Godot expects (`empire_territory.gdextension`).

## Live contract

- Godot class: `TerritorySim`
- Live Play: WorldDataset + SCD1 domain pulls — see skill `eoy-scd1-presentation`
- PresentationTxn = legacy/QA only
- R1: `logistics.rs` may remain as ABI shell; do not re-enable road growth in Play

## Verify

1. Confirm DLL timestamp under `rust/empire_territory/bin/`
2. Run `eoy-qa-lifecycle` (`qa_runner` + relevant smokes)
3. If Godot still loads old code: fully quit the editor/game (Windows locks DLLs)

## Notes

- `.gdextension` comments must use `;` not `#`
- Day-to-day Godot: 4.6+ Steam tools path with a **matching** DLL
