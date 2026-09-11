# Unit metadata

**Status:** Exploratory lore schema for Two Worlds unit cards. **Not** a live World Conquest lock.  
**Combat authority:** Rust `UnitKind` / `KindProfile` (`rust/eon_engine/src/model.rs`). Encyclopedia numbers labeled **live** must match that profile. Horizon numbers are **proposed** and do not spawn as Custom Battle kinds.

In-game: Main Menu → **Lore** → a roster unit. Formation follow-up (templates consume **rank** and, in the line band, **group**): Asana Two Worlds battles, *Per-kind attack interval and unit group classification*.

Think Total War **category** + Dominions-style **stat block and tags**, mapped onto the loop we already have: one tick, many kind profiles (domain + cohesion + reach + speed + altitude + attack interval).

---

## Why these labels exist

Custom Battle templates place by **rank** (screen / line / overwatch / battery / train / air). Within the **line** band, **group** puts melee ahead of hybrid (Attack Column tip / wedge point). Globe World Conquest still only splits Hearthline vs Debt Wings.

**Arm** is the Total War category (what the card *is*).  
**Rank** is the formation band (where a template *puts* it).  
**Group** is the parent stance (melee / hybrid / guns / supply) used to order a band.  
**Domain** is the locomotion plane (already in Rust: land / air / naval).

---

## Closed vocabularies

Do not add a value without a lore or battles card.

### Domain

`land` · `air` · `naval`

### Arm (unit class)

| Arm | Means | Hearthkin now |
|-----|--------|----------------|
| `infantry` | Holds a front | Hearthline |
| `assault` | Shock / breach. Still a front, thicker | Stovebreakers |
| `recon` | Screen. Finds the line | Walk-Mappers |
| `pioneer` | Engineers. Dig the decision in | Ash Wardens |
| `artillery` | Guns. After as shells | Ledger Pieces |
| `armor` | Fighting vehicles | *none yet* |
| `support` | Supply / train. Not a fighter | Rolling Hearths |
| `anti_air` | Files a claim against the sky | Ceiling Clerks |
| `air` | Aircraft | Debt Wings |
| `naval` | Ships | *later* |

**Rolling Hearths are `support`, never `armor`.** Tracked stove ≠ tank.

### Rank (formation band)

Templates should place by rank, not by sprite.

| Rank | Band | Typical arms |
|------|------|----------------|
| `screen` | Ahead of the fighting line | recon |
| `line` | The fighting front | infantry, assault, armor |
| `overwatch` | With or just behind the line | anti_air |
| `battery` | Behind the line, ahead of the train | artillery |
| `train` | Farthest land rear | support, pioneer |
| `air` | Air pads (already bomber corridor) | air |
| `sea` | Water plane | naval |

Assault stays **rank `line`**. Pioneers march in the **train** and work the dirt from there — Compact liturgy, not TW sappers in the first rank.

### Group (parent classification)

Flat closed list. Not a tree. `arm` is the Total War class; `group` is weapon stance / parent job for formation. Artillery, air, support, and anti-air are their own parents (not fake-infantry). No cavalry. No tanks.

| Group | Means | Compact now |
|-------|--------|-------------|
| `infantry_melee` | Close shock | Stovebreakers |
| `infantry_hybrid` | Rifle line that is still a front | Hearthline |
| `infantry_range` | Dedicated ranged infantry | *none yet* |
| `infantry_skirmish` | Screen, not the scrum | Walk-Mappers |
| `infantry_engineer` | Pioneers / sap | Ash Wardens |
| `anti_air` | Claim against aircraft | Ceiling Clerks |
| `artillery` | Guns | Ledger Pieces |
| `support` | Supply / train. Not a tank | Rolling Hearths |
| `air` | Aircraft | Debt Wings |

`infantry_range` is reserved for a future rifle-only line that is not hybrid. Do not invent a ninth Compact job to fill it.

In the **line** band: Attack Column and wedge tip put `infantry_melee` ahead of `infantry_hybrid` (then `infantry_range` if one exists). A Hearthline-only army (kind 0, including 10k stress) stays an infantry line.

### Size class

`person` · `gun` · `wagon` · `aircraft` · `vessel`

### Stats (KindProfile language)

Same names as Rust so we do not grow a second combat dialect.

| Key | Live meaning |
|-----|-----------|
| `hp` | `base_hp` |
| `attack` | `base_attack` |
| `attack_interval` | battle ticks between shots (`UnitKind::attack_interval`). Hearthline **3** is today's land cadence; Debt Wings **32** is today's bomb floor. Viewer records every 3 ticks. |
| `reach` | weapon reach |
| `perception` | who a body looks for |
| `speed` | `move_speed` |
| `cohesion` | 0 ignore guide … 1 glued to slot |
| `vs_air` | small-arms vs aircraft coefficient |
| `blast` | `blast_radius` (0 = single target) |
| `cruise_z` | cruise altitude |
| `regiment_size` | bodies per card |
| `spacing` | center-to-center personal space |

`stats_source`: `live` (must match `UnitKind`) or `proposed` (horizon).

Morale / armor are **not** on the card yet. Squad morale already exists as a battle-brain idea; do not invent a second number until a battles card says so.

### Tags (special rules, not a second category)

Closed. Prefer a tag only when **arm/rank/group does not already say it**.

`poor_vs_air` · `good_vs_air` · `blast` · `overfly` · `shock_breach` · `sap` · `mapping` · `after_shells` · `supply_spine` · `not_a_tank` · `single_target` · `armored` · `fragile` · `slow`

---

## Compact fill (8)

| Unit | Domain | Arm | Rank | Group | Size | Source |
|------|--------|-----|------|-------|------|--------|
| Hearthline | land | infantry | line | `infantry_hybrid` | person | **live** (Soldier) |
| Stovebreakers | land | assault | line | `infantry_melee` | person | **live** (Stovebreaker) |
| Ash Wardens | land | pioneer | train | `infantry_engineer` | person | **live** (AshWarden) |
| Walk-Mappers | land | recon | screen | `infantry_skirmish` | person | **live** (WalkMapper) |
| Ledger Pieces | land | artillery | battery | `artillery` | gun | **live** (LedgerPiece) |
| Rolling Hearths | land | support | train | `support` | wagon | **live** (RollingHearth) |
| Ceiling Clerks | land | anti_air | overwatch | `anti_air` | person | **live** (CeilingClerk) |
| Debt Wings | air | air | air | `air` | aircraft | **live** (Bomber) |

Walk-Mappers domain is **land** (they walk). Arm is `recon`. Group is `infantry_skirmish`.

Live `attack_interval` (ticks): Stovebreakers 2 · Hearthline 3 · Walk-Mappers 4 · Ceiling Clerks 4 · Ash Wardens 6 · Ledger Pieces 8 · Rolling Hearths 16 · Debt Wings 32.

---

## JSON shape

On a roster entry:

```json
"unit": {
  "domain": "land",
  "arm": "infantry",
  "rank": "line",
  "group": "infantry_hybrid",
  "size_class": "person",
  "weapon": "Compact rifle",
  "stats_source": "live",
  "regiment_size": 100,
  "spacing": 3.6,
  "stats": {
    "hp": 100,
    "attack": 12,
    "attack_interval": 3,
    "reach": 70,
    "perception": 70,
    "speed": 2.4,
    "cohesion": 0.42,
    "vs_air": 0.08,
    "blast": 0,
    "cruise_z": 0
  },
  "tags": ["poor_vs_air", "single_target"]
}
```

Encyclopedia is **not** combat authority. If live stats drift from Rust, Rust wins; fix the card.

---

## What this is not

- Not eight playable anatomies.
- Not a silent F6 / barracks / hangar change.
- Not morale, armor, magic paths, or a Dominions bless/curse list.
- Not cavalry, tanks, or a ninth Compact job.
