# Request: SCD1 main tables + domain versioned pulls

## Summary

**Request:** Evolve World Conquest live play so **Rust main tables are the only current sim truth (SCD1)**, and Godot **only pulls rows that are newer than its last monotonic version, per domain (table)**. Godot becomes an apply-only view. We stop relying on dual writes, best-effort field deltas, and periodic “heal” jobs as the way to stay correct.

**Why:** Deltas and parallel caches have **drifted** (land-bridge pulse, missing completed bridges, FPS thrash). Healing (full recal, full snaps, asserts) papers over multi-source-of-truth. Versioned pulls of **current rows** from split domains keep correctness simple and cost proportional to what actually changed.

---

## Full snapshots: when they stay, when they go

### Goal

**Remove routine full snapshots** during live play. In the target design, a **full domain dump** is not part of the normal frame loop.

### When a full pull is still allowed (high level)

| When | Why |
|------|-----|
| **Game start / join / load ready** | Godot has no prior `last_version`; must seed the view from current main tables (`last_version = 0` → entire domain once). |
| **Gap / desync recovery only** | Only under the **explicit policy below** — not on a timer, not because the sim is busy. |

**Risk we must not accept:** loose gap recovery that fires often and **FPS-bombs** the game (full world resync thrash). The rules below are **mandatory** for any implementation of this request.

---

## Gap recovery policy (explicit — anti FPS-bomb)

Gap recovery = a **full** pull of current main-table data used only when incremental `version > last` cannot be trusted. It must stay **rare**. Busy frames use **large incremental** batches (many rows newer than last), **not** full recovery.

### Policy 1 — Default path is only incremental

```text
if last_version is set and pull_since succeeds:
    apply rows with version > last_version
    last_version = high_water
    DONE
```

Full pull is **not** on the happy path. Idle frames with no version advances → empty/near-empty incremental → **no full recovery**.

### Policy 2 — Explicit allow-list of full-pull causes only

Full pull may run **only** when the reason is one of:

| Allowed reason | Meaning |
|----------------|---------|
| `last_version == 0` / unset | Game start or domain never seeded |
| `sim_reset` / match id / sim generation changed | New game or world rebuild |
| Pull **hard error** | DLL/API failure, corrupt response |
| `session_mismatch` | Client `last_version` **greater than** server high_water (wrong instance / reset counter) |
| Optional: checksum fail **after N consecutive mismatches** | Not on the first blip; rate-limited (see Policy 3) |

**Forbidden as full-pull reasons (non-exhaustive):**

- Busy frame / many structures or units updating  
- Enemy AI plan tick  
- Logistics timer / “might have drifted”  
- FPS dip alone  
- Empty incremental when `high_water == last` (that is success: nothing changed)  
- Flaky one-off assert without consecutive confirmation  

> **Mid-match full pull is a bug unless `reason` is in the allow-list above (or rate-limited checksum recovery).**  
> Busy sims use **large incremental only**.

### Policy 3 — Cooldown / circuit breaker

```text
if a full pull for this recovery scope ran within the last COOLDOWN (e.g. 2–5 seconds):
    do NOT full pull again
    log error; keep last good view or pause pulls
    do not spin full → fail → full → fail
```

Prevents FPS death spirals if something is broken.

### Policy 5 — Prefer catch-up incremental over full

If the client is behind but the server can still stream complete incremental batches:

```text
while high_water > last and batch is valid:
    apply batch of rows with version > last   // still only changed rows
    last = batch high_water
```

**Do not** treat “many versions advanced” as a gap. That is a **large incremental** (expected cost proportional to real updates), not full recovery.

Full pull only if catch-up is **impossible** or **broken** (allow-list reason), not because a lot changed.

### Policy 6 — Metrics / logging for every full recovery

Every full pull **must** log once, e.g.:

```text
FULL_RESYNC reason=sim_reset cost_ms=… high_water=… last_was=…
```

If this line appears every second during normal play, **the implementation is wrong** — fix the trigger, do not accept frequent full resync as normal.

### Policy 7 — Budget the full pull if it ever runs

Even start/gap full pulls should avoid a single 50ms+ frame when practical:

- Chunk by domain or row pages across a few frames, **or**
- Cap work per frame with a short “seeding” state  

Start hitch is acceptable; multi-frame seed is preferred over one death frame. Mid-match gap full pull (if it ever fires) must obey Policy 3 cooldown and Policy 6 logging.

### Explicitly out of scope for this request (not adopted)

**Policy 4 (domain-scoped-only recovery) is intentionally not required.**  
Implementations may still pull one domain or several; this document does **not** mandate “structures fail → resync only structures.” Other policies (1, 2, 3, 5, 6, 7) still apply so recovery cannot thrash FPS.

### Gap recovery decision sketch

```text
result = pull_since(last_version)

if last_version == 0 or unset:
    full_pull(reason=start)           # Policy 2
elif result.hard_error or session_mismatch or sim_reset:
    if within cooldown: abort/log     # Policy 3
    else: full_pull(reason=…)         # Policy 2 + 6 + 7
elif high_water > last and batches OK:
    catch_up incremental only         # Policy 5 — NOT full
elif high_water == last:
    no-op                             # success, not a gap
else:
    do not full_pull for "busy" or "felt wrong"
```

---

### What goes away as the *normal* path

| Today (problem) | Target |
|-----------------|--------|
| Full structure table snap when dirty / growth / thrash | **Only** rows with `version > last_structures` |
| Logistics **full recal ~25s** as correctness crutch | Event-driven or derived from structure table; no timer required for truth |
| Full owner/pressure rebuild every N steps | Only changed cells/rows since last domain version |
| Full MultiMesh rebuild every capacity hiccup | Rebuild only for sids/cells that actually changed (or rare gap resync) |

### Spikes become “a bunch of things updated at once”

**Theoretically yes:** after game start, CPU/FFI cost of the pull path should track **how many records actually changed since last pull**, not “the whole world every so often.”

| Situation | Expected cost |
|-----------|----------------|
| Idle, nothing changing | Near-empty pulls → **no process spike from this path** |
| One soldier moves | Small **agents** batch only |
| One outpost grows one road cell | Small **structures** + maybe **roads** batch |
| Many things same frame (AI places + front moves + 10 roads grow + overlay) | **Larger** batch → visible spike **tied to that burst of updates** |
| Game start | One-time full domains → expected load hitch, then incremental |

So process spikes should be **explainable**: “a lot of versions advanced this frame,” not “timer fired a full snapshot / full recal for no user-visible reason.”

Other spikes can still exist outside this pull design (GPU fill-rate, enemy pathfind cost, editor/OS). The request is that **table sync** stops being a source of uncorrelated full-world thrash.

---

## Problem (why we’re requesting this)

### What we see in the product

- Visual / state bugs when Godot and Rust disagree (e.g. structure **CONNECTING** pulse after roads look done; completed land bridges hard to see).
- **FPS cliffs and random-feeling blips** from thrash (full structure pressure, MultiMesh rebuilds, logistics full recal, AI pathfind) rather than only from real change volume.
- Ongoing need for **guardrails and healers**: frozen mirrors, full recal ~25s, full structure snapshots, dual-path refuses, assert contracts.

### Root cause (technical)

| Pattern today | Issue |
|---------------|--------|
| Rust main tables + PresentationTxn patches | Correct direction, but patches can be incomplete or reordered relative to Godot writes |
| Godot `placed_structures` as a live cache | Second writer / second lifecycle → thrash and drift |
| Logistics `target` maintained separately | Needs periodic **full recal** to heal drift from structure list |
| Delta without a high-water mark | Missed updates leave the view permanently wrong until a big resync |

So: **not enough single source of truth**, and **incremental transport isn’t strictly “newer than last pull.”**

---

## What we are requesting to do

### 1. Treat Rust as SCD1 current-state store

For each sim domain, keep **only current values** (overwrite on change). No Godot-owned sim lifecycle for those fields under live play.

**Domains (tables / buckets), split so unimpacted data is not pulled:**

| Domain | Main table content (current only) |
|--------|-----------------------------------|
| **Territory / grid** | Owners, pressure (as needed), claimable |
| **Structures** | Kind, team, position, state, path_built, path keys/len, health, timers as applicable |
| **Logistics / roads** | Built road cells (growth driven from structures, not a parallel “truth”) |
| **Agents** | Soldiers (position, team, living set) |
| **Bombers** | Bombers / bomb events for presentation |
| **Wallet** | Resource balances (and supply if/when owned there) |

**Rule:** Godot may send **commands** (place, plan AI intent). Only Rust mutates domain rows and bumps versions.

### 2. Monotonic versions (not wall-clock as the pull key)

- Global and/or per-domain **monotonic counter** (e.g. `u64` epoch): increments on every real write.
- Optionally per-row `version` set to that epoch when the row changes.
- Godot stores `last_version` **per domain** (e.g. `last_structures`, `last_agents`, …).

**Pull contract (conceptual):**

```text
pull_since(domain, last_version) →
  {
    high_water_version,
    rows: [ full current row for each record with version > last_version ]
  }
```

- **Game start:** `last_version = 0` → full current domain once, then incremental forever (unless gap).
- **Gap / desync:** full domain pull once, reset `last_version` — no merge-both-sides.

### 3. Incremental = only impacted domains and rows

Example:

- Soldier moves → only **agents** with `version > last_agents` are pulled.
- Outpost path grows → only that **structure** row (and maybe **roads** cells); wallet/agents untouched.
- Owner flip → **territory** changed cells only.

**Agreed mental model:** don’t call tables that weren’t impacted; within a table, only records newer than last version.

### 4. Godot is apply-only presentation

- Apply pulled rows by **overwrite** of local view state (MultiMesh, markers, HUD).
- Disposable caches: if wrong, rebuild from main table via full domain pull (start or gap only).
- **No** inventing `path_built` / `state` / owners in GDScript under live WorldDataset.

### 5. Retire or demote healers that paper over dual truth

As domains become version-pull based:

- Logistics **full recal** becomes optional audit or event-driven rebuild from StructureStore—not required for correctness on a timer.
- Full structure snap becomes **game start + gap recovery only**, not the normal growth path.
- PresentationTxn evolves into (or is replaced by) **versioned domain pulls** of current rows; field-only patches are optional optimizations, not the contract.

### 6. Keep fail-closed live authority

- Live play still requires Rust DLL + WorldDataset contract.
- No silent CPU dual-sim as production path.

---

## What we are *not* requesting (non-goals)

- New game modes, multiplayer, or map size changes.
- Pure balance retunes.
- Rewriting history of removed modes.
- Throwing away Rust sim or Godot rendering.
- Perfect GPU FPS measurement in headless CI.
- SCD2 / full history of every past state (only **current** + version for pull).
- Claiming **zero** FPS spikes forever (GPU, pathfind, and large simultaneous updates can still cost; they should be **tied to real work**).

---

## Why we are requesting it

### Correctness

| Goal | How this helps |
|------|----------------|
| Single source of truth | Sim state lives in one place (Rust tables) |
| No dual-lifecycle bugs | Completes/activates only in Rust; view follows |
| Recoverable desync | Gap → full domain pull, table always wins |
| Predictable land bridges / construction | State machine not split across engines |

### Performance

| Goal | How this helps |
|------|----------------|
| Pay for what changed | Soldier move doesn’t resync all structures |
| Avoid thrash | No full-structure / MultiMesh wipe loops from dual writers |
| Fewer uncorrelated blips | No mandatory full recal / full snap as correctness crutches mid-game |
| Explainable spikes | Large frame cost ≈ large batch of version bumps that frame |
| Stable ~60 FPS mid-game | Incremental work bounded by change volume after start |

### Maintainability

| Goal | How this helps |
|------|----------------|
| Simple mental model | “Current row + version > last” |
| Clear API | Per-domain `pull_since` |
| Less special-case glue | Fewer frozen mirrors / refuse paths / thrash guardrails as primary design |
| Aligns with audit direction | WorldDataset + PresentationTxn matured into explicit SCD1 + version pulls |

### Product / player experience

- Construction and bridges look and behave consistently.
- FPS dips map to real work (many updates, AI pathfind, GPU), not silent cache drift.
- Easier to reason about correctness → look at Rust tables.

---

## Success criteria

1. **Live play:** Godot does not advance structure `state` / `path_built` / road built as authority; only applies pulls.
2. **Per-domain `last_version`:** After N frames of only unit motion, structure/wallet pull batches are empty (or near-empty).
3. **No routine full structure/owner dumps mid-match** except explicit gap recovery.
4. **Game start:** one full domain seed; then incremental only.
5. **Missed updates:** forced skip of pulls then one full domain resync restores view without timer-based healers.
6. **Land bridges / outposts:** complete without CONNECTING pulse thrash; completed bridge remains visible from table data.
7. **QA (locked #8):** **new dedicated test harness** for the version-pull contract must pass **before merge** (not only existing qa_runner + light checks). Include: start seed, incremental mid-match, empty pull when domain idle, full resync allow-list + cooldown, no dual authority, multi-domain isolation.
8. **Docs:** DESIGN/RUST describe SCD1 domains + monotonic pull; PresentationTxn not on live path; dual-path marked legacy/QA-only if retained.

---

## Approved implementation decisions (locked before code)

Stakeholder answers locked for the implementation handoff. **Do not re-litigate in code without updating this section.**

| # | Decision | Choice | Meaning for implementers |
|---|----------|--------|---------------------------|
| **1** | Scope of first ship | **C — all domains at once** | Territory/grid, structures, logistics/roads, agents, bombers, and wallet all move to SCD1 + versioned `pull_since` in the **same** delivery — not structures-only phase 1. |
| **2** | PresentationTxn | **B — replace entirely** | Do **not** keep PresentationTxn as a parallel live path. Versioned domain pulls **replace** the live presentation change-feed contract (txn may be deleted or reduced to non-live/QA-only if still needed for goldens — live Play must not dual-feed). |
| **3** | Version counter shape | **A — per-domain epoch** | Each domain has a monotonic `u64` epoch; on write, bump domain epoch and set that row’s `version` to the new epoch. Godot stores `last_version` **per domain**. |
| **4** | Pull cadence | **A — per domain per frame** | After sim/logistics (or equivalent once per frame), call `pull_since(domain, last)` for each domain. Empty batch when nothing newer — still the happy path. |
| **5** | Structure (and domain) payload | **A — full current row** | Incremental pull returns **full presentation/current rows** for changed ids (overwrite apply). Not minimal field patches as the contract. |
| **6** | Godot authority | **A — absolute under live** | Live WorldDataset: Godot **never** authors `state` / `path_built` / owners / road built / wallet balances as truth. Commands only (place, intents); lifecycle and values only in Rust; Godot apply-only from pulls. |
| **7** | Gap recovery knobs | **Use defaults + hard anti-thrash** | Defaults: full-pull **cooldown 3 s**; checksum consecutive fails **3** before optional full (or disable checksum-full in first cut if safer); **no MAX_GAP force-full** (Policy 5 catch-up incremental only); chunk full seed when large (Policy 7). **Critical:** gap full pull must **not** fire routinely or FPS-bomb — Policies **1, 2, 3, 5, 6, 7** are mandatory; mid-match full outside allow-list is a **bug**. Prefer logging + cooldown over aggressive resync. |
| **8** | QA bar before merge | **B — full new test harness first** | Do **not** merge on “existing qa_runner green + a few checks” alone. Build a **dedicated test harness** for the version-pull contract (start seed, incremental-only mid-match, empty pull when idle domain, allow-list full resync, cooldown, no dual authority, multi-domain isolation) and require it **before** merge of the live path. |

### Implications of these choices

- **All domains at once (#1) + replace PresentationTxn (#2)** is a **large, cross-cutting** change (Rust FFI, Screen presentation path, globe apply, QA). Expect a single architectural cutover for live play, not a soft dual-stack.
- **Per-frame pull_since all domains (#4)** must stay cheap when idle (empty high-water checks / empty row lists) so frame cost stays near zero when nothing changed.
- **Full row payloads (#5)** favor correctness over minimal FFI size; still only for `version > last`.
- **Harness-first QA (#8)** means implement tests that prove the contract **before** declaring the feature merge-ready.

### Gap recovery defaults (from #7) — explicit numbers

| Knob | Value | Notes |
|------|--------|--------|
| Full-pull cooldown | **3 seconds** | Per recovery scope; circuit breaker (Policy 3) |
| Checksum → full pull | After **3** consecutive mismatches | Or **off** in first cut if it causes false full pulls; never on first blip |
| MAX_GAP force-full | **Off** | Large backlog = catch-up **incremental** (Policy 5), not full snap |
| Full seed budgeting | **Chunk / multi-frame** when row count is large (Policy 7) | Avoid single death frame at start |

**FPS-bomb ban:** If `FULL_RESYNC` logs appear every second in normal play, the build **fails** the request — fix triggers, do not ship.

---

## Suggested implementation shape (planning order)

Given **#1 all domains** and **#2 replace PresentationTxn**, order is integration-oriented rather than “structures-only MVP”:

1. **Version infrastructure** — per-domain epochs, row `version` on write, `pull_since` / `pull_full` APIs for every domain in the table above.
2. **Rust writers only** — all live mutations bump the correct domain epoch; remove dual write paths for structure complete / path_built / etc.
3. **Godot cutover** — Screen/globe use domain pulls only; **remove live PresentationTxn** consume path; apply-only overwrite.
4. **Demote healers** — logistics timer full recal not required for truth; mid-game full snaps only via gap allow-list.
5. **Test harness (#8)** — new dedicated suite proving contract **before** merge; then wire residual smoke into broader QA as needed.
6. **Docs** — DESIGN/RUST point at SCD1 + domain pulls; mark legacy txn/dual path QA-only if retained.

---

## Decision to approve

**Approve** moving live World Conquest to:

- **SCD1** current-state main tables in Rust  
- **Domain-split** tables so unimpacted domains are not pulled  
- **Monotonic version** high-water pulls (`version > last_seen`) of **full current rows** for impacted records  
- **Godot apply-only** views  
- **Full snapshots only at game start (and rare gap recovery under Policies 1–3, 5–7)** — not as ongoing mid-game process  
- **Implementation locks:** all domains in one delivery; **replace** PresentationTxn on live path; per-domain epoch; per-frame `pull_since`; full-row payloads; absolute no Godot sim authority live; gap defaults with anti-FPS-bomb; **new test harness before merge**

**Because** it fixes drift at the architecture level, makes load proportional to real change, and matches: **one truth, incremental views, no dual sim.**

---

## Glossary (short)

| Term | Meaning |
|------|---------|
| **SCD1** | Only current values in the table; updates overwrite (no history table required) |
| **Domain** | One main table / category (structures, owners, roads, agents, …) |
| **Monotonic version** | Counter that only increases; “newer than last pull” |
| **Full snapshot / full domain pull** | Send all current rows in a domain (start or gap only in target design) |
| **Incremental pull** | Send only rows with version &gt; client last_version |

---

*Related: [DESIGN.md](../DESIGN.md), [RUST.md](../RUST.md), [docs/INDEX.md](INDEX.md).*
