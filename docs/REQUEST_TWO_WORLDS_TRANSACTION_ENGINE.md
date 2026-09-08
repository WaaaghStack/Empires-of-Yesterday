# Request — Two Worlds, One Transaction Engine (Total War × Dominions 6 × EOY)

**Status:** Exploratory proposal. Not accepted, not scheduled, no code yet. Captures a design
direction explored with the product owner so downstream agents have a contract to build to
*if* it is greenlit. Design-lock changes below are **PROPOSED** and require `product-manager`
signoff + a `DESIGN.md` edit before any implementation (see `eoy-design-lock-change`).

**Explored:** 2026-09-07

**Implementation status (2026-09-08):** The **engine spine** is implemented and unit-tested as the
godot-agnostic `rust/eon_engine` crate (deterministic replay, double-entry reconciliation, dominion
field, agents, squad+LOS battles to 1000 units, WEGO turns, win checks, nested battle result txns)
and wired into the `empire_territory` GDExtension as `TwoWorldsEngine`. The HD-2D battle viewer
plays baked tracks (diorama, banners, tracers, 8-way billboards). Live World Conquest QA + Rust/CPU
parity unaffected. Branch: `cursor/mvp-two-worlds-engine-0600`.

---

## 1. Vision

Reframe Empires of Yesterday from a single real-time fluid battle into a turn-based grand
strategy game that meshes three influences:

- **Total War** — campaign *structure*: provinces, armies, pre-battle **formations**, and a rich
  **agent meta-game**; plus **auto-resolve**.
- **Dominions 6** — the *soul*: a slow spreading **Dominion**, an **order-of-operations**
  simulation engine, and **auto-resolved battles you set up but do not control**.
- **EOY (today)** — the *engine and identity*: a visible flowing field on a 3D globe, tile
  ownership + cancellation, the Rust WorldDataset authority, SCD1 wide-row presentation, and
  deterministic replay tape.

The player **does not own the battle**. They shape it beforehand (composition + formation +
stance), then watch a deterministic **replay**. Hands-on skill lives in the campaign layer
(dominion steering, agents, army positioning), not in battle micro.

## 2. Two worlds, one engine (the spine)

There are **two worlds — the World (globe/campaign) and the Battle** — and they are the **same
three-layer pattern instantiated twice**:

| Layer | The World (globe) | A Battle |
|-------|-------------------|----------|
| **Authority (narrow)** | ordered transaction engine over normalized tables, resolved **per turn** | same engine, resolved **per tick** |
| **Transaction log** | the ordered record of what happened this turn (source of truth) | the ordered record of each tick (source of truth) |
| **Presentation (wide rows)** | globe **turn playback** the user watches | **HD-2D replay** the user watches |

Key consequences:

- **No real-time.** A world turn is *resolve → project → watch*, exactly like a battle — just at
  turn scale instead of tick scale. Ending a turn folds the transactions, then the wide-row layer
  plays the turn back on the globe.
- **The transaction log is the canonical replay** for both worlds. Wide/denormalized rows (SCD1
  domain pulls, EYTR frames, RGBA bakes) are **read-only projections** for presentation/replay —
  they are written *to*, never read *back into* sim logic. Wide rows never do the hard entity work.
- **Battles are nested, not parallel.** During world-turn resolution a `ResolveBattle(province)`
  transaction spawns the battle as a **sub-simulation** (its own tick-scale log + baked replay) and
  emits a **result transaction** back into the world log. Seeds thread world → battle, so the whole
  turn (globe changes *and* every battle inside it) is reproducible from the world log alone.
- This reuses today's **SCD1 wide-row presentation** as the user-facing layer for both worlds; the
  evolution is swapping what sits *under* it (real-time array sim → turn-based transaction engine)
  and adding **turn playback**.

> Naming caution: this authority engine is **not** the legacy `presentation_txn.rs` (a QA-only
> *presentation* change feed). This is the *sim core itself* expressed as an ordered transaction log.

## 3. Order of operations (Dominions-style)

A turn resolves as a strict, ordered sequence of **phases**, each a batch of transactions applied
in a deterministic order; transaction `X` reads state, computes result `Y`, mutates, then the next
runs against updated state.

- **Determinism is the contract:** fixed phase order, deterministic intra-phase ordering (by id /
  initiative), a single seeded PRNG threaded through transactions, single authority (Rust).
  `initial state + seed + transaction order → identical result`, always.
- **Fields vs entities (important nuance):** discrete entities (units, squads, agents, commanders,
  rituals, provinces, structures, wallets) are **transactions** over **narrow tables**. The
  **Dominion field** is intrinsically a **grid stencil** (every land tile updates from neighbors) —
  it stays an efficient **array kernel**, but is **invoked as one scheduled phase** in the order of
  operations. So the pipeline is still one deterministic ordered sequence; the field math is an
  implementation detail *inside* a phase. No wide *rows* drive *entity* logic.

Illustrative world-turn phase order (to be finalized by PM/architect):
`income/gems → upkeep → agent actions → rituals/miracles → army movement → ResolveBattle(...) →
SpreadDominion (field phase) → corruption/unrest → events → win checks`.

## 4. Dominion model (passive + amplifiers, "corruption" style)

- **Passive baseline:** every dominion-owned tile emits a tiny spread per turn — a **slow tide**,
  **height-independent** (ignores elevation; water is the main barrier).
- **Amplifiers stack on top:** **temples** (fixed high-output sources), **prophets** (mobile
  high-amplitude sources — a walking pump), **agents** (temporary boosts / enemy suppression).
  This is the existing source-injection system (`home pump` / `outpost pump` / `Battery`→`Surge`).
- **Cancellation retained:** overlapping friendly/hostile dominion subtract, as today.
- **Corruption feedback:** where enemy dominion soaks a province you own → **unrest**, lost income,
  and (if neglected) **rebel/monster stacks**. Makes the slow tide a constant tug-of-war and keeps
  agents/prophets relevant. Think Total War chaos corruption + Dominions dominion pressure.
- Mechanically reuses the pressure arrays + cancellation; relaxes `effective_height` for the field
  (see proposed lock change).

## 5. Turn model

- **WEGO simultaneous resolution** (all factions submit orders; the turn resolves at once) — fits
  hands-off battles, scales to many factions, and enables async/PBEM multiplayer later.
- **Turn playback on the globe:** resolve → project to wide rows → watch the tide creep, armies
  slide, provinces flip. (MVP may start as snap-to-state + a scrollable event/transaction feed.)

## 6. Battles

**Resolution (authority, Rust-only, deterministic):**

- **Squad/regiment brain** owns *guides* — formation field, facing, engagement line, who the body
  is meant to fight, **cohesion**, **morale** (break → the squad flees). Formation is **not** a rail:
  it is the company order the individuals drift around.
- **Each body fights individually.** It is attracted toward its slot, then within a local
  **perception/LOS radius** picks a valid enemy and attacks; own HP + death. Fighting a local target
  beats dressing ranks. ("The line is the intent; the soldier is the fight.")
- **One loop, many kinds.** Land / air / (later) naval share the tick + spatial hash; each kind is a
  **profile** (domain, cohesion, reach, speed, altitude). Tanks hug the guide, soldiers peel off to
  shoot, zombies swarm, planes use an altitude corridor. Prototype roster is soldiers + bombers;
  the schema must accept tanks, aliens, etc. without a second engine.
- Runs as a fixed-timestep transaction loop with a **spatial hash** for neighbor/LOS queries
  (≈O(1)); parallelizable (rayon). Resolved **once**, then **baked to the wide EYTR replay**.
- **Determinism discipline** (fixed iteration order, seeded PRNG, consistent float handling) is the
  main engineering risk; resolve solely in Rust — no second implementation to keep in parity.
  The viewer never picks targets.

**Presentation (Dominions free-cam × Octopath HD-2D):**

Visual bar is locked in [REQUEST_BATTLE_VISUAL_READ.md](REQUEST_BATTLE_VISUAL_READ.md): it has to
**look like a fight** (tableau → march in formation → halt and fire → front holds → rout home → chase).
Centroid-seek during a standing fight is a defect; chasing a broken army is the break beat. Realism is the *picture*, not
ballistic fidelity.

- **Diorama landscape** themed from the contested province's biome/elevation
  (`WorldConquestMapGenerator`). Terrain that does *not* matter to the Dominion tide *does* matter
  here (chokepoints, high ground) and for army movement cost.
- **Free orbit/pan/zoom camera** (Dominions 6 style), reusing the globe orbit camera on a flat slab.
  Default framing shows **both armies and the contact band**; auto-rotate is off during the fight.
- **Billboard sprites** with **directional facing frames** (4-way min, **8-way** preferred for a
  free camera) so units read correctly from any angle; **MultiMesh / GPU instancing** for the mass.
- **Scale: 1000+ units minimum.** Achieved by *resolve-once → bake replay* (viewer only interpolates
  baked transforms + **state flags** — idle/march/aim/fire/hit/dead/rout) plus **LOD** (near = full
  anim/facing; far = static billboard / density blobs + banners/dust). Mass + banners + casualties
  sell "sizable" more than raw count.
- **Art scope for the prototype: soldiers + bombers only** (existing pixel billboards). Expand the
  roster (and facings/anims) later.

## 7. Agents meta-game (Total War)

Because battles are hands-off, **agents are the primary skill lever**. Archetypes tuned to this
world (levels, traits, risk of capture/death):

- **Prophet / Priest** — accelerate Dominion spread locally (mobile amplifiers).
- **Spy** — reveal provinces, sap enemy Dominion, sow unrest.
- **Assassin** — remove enemy generals/agents (generals modify auto-resolve, so this swings battles).
- **Diplomat** — relations, bribes, incite revolt.
- **Mage / Scout** — find magic sites / gems, cast remote rituals.

## 8. Win conditions (blend)

- **Conquest** — own all reachable land (current EOY).
- **Dominion kill** — erase the enemy's faith field (reuses today's `zero-power` victory).
- **Ascension** — hold enough **Thrones of Ascension** (objective-driven, faster clock).

## 9. Reuse vs build

| Reuse (already in repo) | Build new |
|-------------------------|-----------|
| Rust WorldDataset authority + rayon + grid/spatial structures | Ordered transaction engine + narrow tables + phase scheduler |
| Pressure arrays + cancellation → Dominion/corruption field | Dominion field as a scheduled phase (slow, height-independent) |
| Source injection (pump/Battery/Surge) → temples/prophets/miracles | Corruption→unrest feedback + rebel spawns |
| SCD1 wide-row presentation (`Scd1DomainPull`) → user-facing layer | Globe **turn playback** |
| Replay tape (EYTR) + RGBA bake → baked replays | Per-unit transform/state replay tracks |
| Pixel billboards + MultiMesh instancing | HD-2D diorama scene + slab generator + LOD |
| Globe orbit camera → free battlefield camera | Squad-brain + individual-LOS battle resolver |
| `EnemyStrategy` → faction AI | WEGO turn controller; agents meta-system; light diplomacy |

## 10. PROPOSED design-lock changes (pending PM accept + DESIGN.md edit)

Use the `eoy-design-lock-change` template. **None are accepted yet.**

```markdown
## Lock change (PROPOSED)
- IDs: (new) real-time → turn-based; effective_height (core); F5; F6
- From → To:
  - Real-time continuous sim → turn-based WEGO resolve + playback (two-worlds engine).
  - effective_height (H = pressure + elevation, mountains slow flow) → RELAXED for the Dominion
    field: spread is height-independent (elevation still matters for armies + battle terrain).
  - F5 (win ignores units / land-or-zero-power only) → add Dominion-kill (already ~zero-power) and
    Thrones/Ascension wins.
  - F6 (5/structure, 100 global caps) → army-scale unit counts (1000+ per battle).
- Player impact: game becomes a turn-based globe strategy; faith is a slow steerable tide; battles
  are large, auto-resolved, watchable HD-2D replays; agents carry player skill.
- Docs touched: DESIGN.md (locks + Direction + dictionary), docs/INDEX.md, this request.
- Code / QA follow-ups: transaction engine, field phase, battle resolver, turn controller, HD-2D
  viewer; new QA goldens for deterministic turn/battle resolution.
```

## 11. Open decisions

- **World-turn playback fidelity:** animate the full turn vs snap-to-state + event/transaction feed
  (MVP: snap + feed, animate later).
- **Battle-log persistence:** keep full tick-logs for rewatch, or persist only result + seed and
  re-sim on demand (storage tradeoff; symmetry makes either trivial).
- **Sprite facing count:** 4-way vs **8-way** (drives art budget; 8 reads better under free camera).
- **Individual bodies:** soft collision/press (lines form/crush; costlier, more epic) vs free overlap
  (cheaper, more Dominions-ish). Visual read still requires a **front** — overlap must not turn the
  army into a pile or a commute across the map ([REQUEST_BATTLE_VISUAL_READ.md](REQUEST_BATTLE_VISUAL_READ.md)).
- Confirmed already: squad-brain + **individual LOS** combat; **free-ish** Dominions-style camera;
  auto-resolved **watchable replays**; **passive + amplifier** Dominion; **soldiers + bombers** first.

## 12. Workstream / agent plan

One agent per PR-sized unit of work, coordinated via `eoy-multi-agent-handoff`, QA-gated by
`eoy-qa-lifecycle`:

1. **Foundation (this doc + skills)** — the transaction-engine + battle-resolve contract on record.
2. **`product-manager`** — user stories + acceptance; formalize the design-lock changes.
3. **Parallel implementation agents** (each own branch/PR):
   - transaction-engine core + narrow tables (`data-architect` + `coding-architect`)
   - Dominion field as a scheduled phase (grid stencil)
   - battle resolver (squad-brain + individual-LOS) → baked replay
   - HD-2D battle viewer (soldiers + bombers)
   - WEGO turn controller + globe turn-playback
   - agents meta-system + light diplomacy

## 13. Non-goals / status

- **Exploratory only** — nothing here is committed to the ship target or the design locks.
- **No engine code** in the foundation pass; **art deferred** (reuse soldier/bomber billboards).
- See skills: `eoy-sim-transaction-engine`, `eoy-battle-resolve`.
