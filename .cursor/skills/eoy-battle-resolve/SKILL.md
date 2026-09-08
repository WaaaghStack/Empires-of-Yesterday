---
name: eoy-battle-resolve
description: Empires of Yesterday proposed auto-resolved battles — squad/regiment brains + individual line-of-sight combat, resolved deterministically in Rust and baked to a watchable HD-2D replay (Octopath-style sprites, Dominions-style free camera, 1000+ units). Use when designing/implementing battle resolution, the battle replay format, or the HD-2D viewer.
---

# EOY battle resolve (proposed)

> **Status: exploratory proposal, with a working slice on `cursor/mvp-two-worlds-engine-0600`.**
> Depends on the turn-based reframe and its design-lock changes (`eoy-design-lock-change`).
> Players **do not control battles** — they set them up, then watch a deterministic replay.

## Canon

- [docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md](../../../docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md) — full design
- Companion skills: `eoy-sim-transaction-engine` (the engine this runs on), `eoy-scd1-presentation`
  (wide-row replay), `eoy-rust-gdextension`, `eoy-qa-lifecycle`, `eoy-ui-theme`

## Model: resolve coarse, fight fine

- **Rust is the only combat authority.** The HD-2D viewer interpolates the bake. It does not target,
  damage, or path.
- **Squad/regiment brain** owns *guides*: formation field, facing, engagement line, who to engage,
  **cohesion**, **morale** (break → whole squad flees). Formation is an attractor, not a rail.
- **Each body fights individually.** Bias toward its slot; in local **perception/LOS** pick a valid
  enemy and attack (own HP + death). Local fight beats dressing ranks. Perception is **not** scaled
  with the 5× slab — squad guides cover the march; whole-map per-body search made 3k+ resolves hang.
  → "The line is the intent; the soldier is the fight."
- **One loop, many kinds.** Kind profile = domain (land/air/sea) + cohesion + reach + speed +
  altitude. Same tick/hash for soldiers, tanks, zombies, aliens, planes; naval later. Prototype art
  is soldiers + bombers only.

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

Visual contract: [docs/REQUEST_BATTLE_VISUAL_READ.md](../../../docs/REQUEST_BATTLE_VISUAL_READ.md)
(form up → halt → fire → hold; no centroid-jog to the far edge). Realism is the picture, not the ballistics.

- **Diorama slab** themed from the province biome/elevation (`WorldConquestMapGenerator`).
- **Free orbit/pan/zoom camera** (Dominions 6 style) — right-drag orbit, wheel zoom, **WASD / arrows** pan the look-at across the slab. Default framing shows both armies; auto-rotate off during the fight.
- **Billboard sprites**, **directional facing frames** (4-way min, **8-way** preferred for a free
  camera), rendered via **MultiMesh / GPU instancing**. Bake `facing` + anim state, not just `x,y,alive`.
- **10000-body stress cap** on the same resolver (Custom Battle **10k stress** fills 50 inf per side at 100). Combat reach is unchanged; the slab is 5× (1000×600). Live World Conquest F6 is untouched.
- **Prototype art scope: soldiers + bombers only.** Soldiers play an 8-frame run/shoot sheet from baked state (GPU UV slice). Bombers keep a single stamp. Globe World Conquest stamps are unchanged.
- **No per-unit banners** on the replay slab.
- **Shots travel:** fire ticks spawn short streaks that move shooter → aim, then vanish. Hit tint is a brief flash, not a held glow. No second combat brain.
- **Even 1× playback.** 1× is the human-readable pace (the old 0.5× clock). Player can slow (0.25× / 0.5×) or speed up (2× / 4× / 8×).
- **Press through.** Regiment orders pick a lane, then the guide closes on that enemy. Halt is weapon reach, not a river parking band.
- **Bombers** overfly, drop a blast, continue the pass, then come around again. Infantry AA is weak (~50 soldiers to kill one bomber). Blasts launch land bodies (baked `z`); not always lethal.

## Reporting (accounting model)

Battles follow the same **ledger → report** discipline as the world (see
`eoy-sim-transaction-engine` § Accounting model):

- Each tick **posts balanced transactions**: damage debits target HP, a death posts a removal, morale
  shifts are posted — no side-channel mutation. Conserved quantities (roster counts, HP pools) balance.
- The **wide EYTR replay is the report**: a one-way projection of the battle journal. Roster/casualty
  totals in the replay must **reconcile** with the posted deaths (trial-balance the outcome).
- The battle **outcome posts back to the World ledger as a single balanced result transaction**
  (province flip + casualties + XP), with provenance linking to the battle log for drill-down/rewatch.

## Change checklist

- [ ] Squad brain change vs individual-combat change — kept on the right tier? Formation still a guide (cohesion), not a rail?
- [ ] Preset formations (Line / Double / Column / Wedge) space regiment *centers*; individuals still break slots to fight.
- [ ] Directional orders are **per regiment** (Custom Battle); army-wide values are defaults only. Rear wraps the field. Land paths around solid hills; river stays a ford.
- [ ] Custom Battle builder is Total War cards + RMB-drag facing — no GDScript combat authority.
- [ ] New unit kind is a **profile** (domain/cohesion/reach), not a new resolver?
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
