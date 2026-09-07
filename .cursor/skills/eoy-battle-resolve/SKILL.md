---
name: eoy-battle-resolve
description: Empires of Yesterday proposed auto-resolved battles — squad/regiment brains + individual line-of-sight combat, resolved deterministically in Rust and baked to a watchable HD-2D replay (Octopath-style sprites, Dominions-style free camera, 1000+ units). Use when designing/implementing battle resolution, the battle replay format, or the HD-2D viewer.
---

# EOY battle resolve (proposed)

> **Status: exploratory proposal.** Not built, not accepted. Depends on the turn-based reframe and
> its design-lock changes (`eoy-design-lock-change`). Players **do not control battles** — they set
> them up, then watch a deterministic replay.

## Canon

- [docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md](../../../docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md) — full design
- Companion skills: `eoy-sim-transaction-engine` (the engine this runs on), `eoy-scd1-presentation`
  (wide-row replay), `eoy-rust-gdextension`, `eoy-qa-lifecycle`, `eoy-ui-theme`

## Model: resolve coarse, fight fine

- **Squad/regiment brain** owns *orders*: where the body moves and who it engages (advance to X,
  charge squad B, hold, flank, rout), plus **cohesion** and **morale** (break → whole squad flees).
- **Individual soldier** moves toward its formation slot in the squad's target area, and within a
  local **perception/LOS radius** picks the nearest valid enemy and attacks; has its own HP + death.
  → "They all head to X, but each one fights whoever is in front of them."

## Resolution rules (authority)

1. **Rust-only, deterministic.** Fixed-timestep transaction loop on the `eoy-sim-transaction-engine`;
   **spatial hash** for neighbor/LOS queries (≈O(1)); rayon-parallel where safe. Fixed iteration
   order + seeded PRNG so the replay equals the resolved outcome. No GDScript battle authority.
2. **Resolve once, then bake.** Emit the outcome (winner, casualties, morale) **and** per-unit
   transform/state tracks (marching/attacking/dying) to the **wide EYTR replay** (`BattleReplayTape` /
   `BattleReplayPack`). Viewing only interpolates baked data — never re-runs combat.
3. **Nested in the World turn.** Invoked by a `ResolveBattle(province)` world transaction; returns a
   result transaction to the world log. Seed threads from the world turn (reproducible).
4. **Inputs:** army composition + formation + stance (pre-battle), general/agent modifiers, local
   Dominion strength, and province terrain (chokepoints/high ground; terrain matters here even though
   the Dominion tide ignores height).

## Presentation (HD-2D × Dominions free-cam)

- **Diorama slab** themed from the province biome/elevation (`WorldConquestMapGenerator`).
- **Free orbit/pan/zoom camera** (Dominions 6 style) — reuse the globe orbit camera on a flat slab.
- **Billboard sprites**, **directional facing frames** (4-way min, **8-way** preferred for a free
  camera), rendered via **MultiMesh / GPU instancing**.
- **1000+ units minimum:** feasible because it is baked-replay playback; add **LOD** (near = full
  anim/facing; far = static billboard / density blobs + banners/dust).
- **Prototype art scope: soldiers + bombers only** (existing pixel billboards). Expand roster later.

## Change checklist

- [ ] Squad brain change vs individual-combat change — kept on the right tier?
- [ ] Deterministic (fixed order + seeded PRNG)? Spatial-hash queries, not O(n²)?
- [ ] Replay tracks (per-unit transform + state) updated as a projection only?
- [ ] Result transaction surfaced to the World log (`eoy-sim-transaction-engine`)?
- [ ] Facings/LOD budget respected for 1000+ units? Reuse MultiMesh + billboards?
- [ ] Design-lock impact (F6 caps, F5 wins)? → `eoy-design-lock-change`.
- [ ] Rebuild DLL (`eoy-rust-gdextension`) + deterministic battle goldens (`eoy-qa-lifecycle`).

## Anti-patterns

- Letting the player micro the battle (it is set-up-then-watch).
- Non-deterministic resolve (replay would diverge from outcome).
- A second battle sim in GDScript to keep in parity.
- Per-mesh (non-instanced) units — kills the 1000+ target.
- Reading wide replay rows back into resolution logic.
