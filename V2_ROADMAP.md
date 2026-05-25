# Empires of Yesterday — V2 roadmap (shipped)

*May 23, 2026 — V2 master plan implementation complete.*

## Campaign navigation (post-V2)

- Default run: **Carrier → Navigation (branching graph) → tactical mission × N → boss → Run Summary**
- `CampaignGraphData.gd` / `CampaignGraphGenerator.gd` — seeded DAG (battle / elite / boss)
- `CampaignNavigation.tscn` — path pick + squad sidebar
- Legacy **planet run** still available: Main Menu → More… → Legacy planet run

## V2 pillars (delivered)

### Commander comfort
- Squad roster: sector, doctrine, HP%, status (ENGAGED / MOVING / EXTRACTING)
- Auto [O] objective doctrine per squad on BEGIN + sector auto-assignment
- Comms default **Priority** (Alerts + Objective)
- Objective comms beats: 50% nests, last nest, queen wake, extract open
- Hive-Hater: **+20% damage vs hives** (combat-time, not just stat passive)

### Real-time command
- **No global pause** — `MissionState.is_unit_actions_frozen` only during deploy selection / mission end
- **SPACE** = sector overlay (combat continues)
- Orbital abilities usable during combat
- Order target highlight on right-click (no ghost path lines)

### Pace & hives
- `HivePressure.gd` — biome + mutator spawn tuning
- Planet map **12–16 rooms** (compressed from 18–24), **1–2 nest hives**, **2–3 evolution nodes**
- Evac opens after Overmind destroyed (no timed extract window)

### Clarity
- `CommsTemplates.gd` military tone
- Minimap icons: hive, extract, evolution, hive telegraph arc
- Hive spawn telegraph **1.5s**, hive damage comms, extract banner pulse

### Performance
- `MAP_ENEMY_CAP` **22** living enemies; hives skip waves at cap
- See [PERFORMANCE.md](PERFORMANCE.md)

### Variety
- Mutators: **Quiet Deck**, **Accelerated Swarm**, **Reinforced** (Orbital Carrier toggles)
- Evolution **2-choice** pick UI at nodes
- New synergy chain: Stim Injector → Neural Uplink → Predator Instinct

### Polish
- Legacy ops under **More…** submenu
- Colony biome tile placeholders + corridor tile rendering
- QA extended for 1–2 hives, unpaused start, mutators

## Strategic depth (shipped)

- Per-node **mutators** on campaign graph + carrier mutators merged at mission start
- **Sector reward** screen after combat (evolution / heal / biomass)
- **Rest / Armory / Intel Broker** event nodes on navigation map
- Navigation **biomass services**: heal, intel reveal, recruit draft
- **Flanker** enemy archetype; **SwarmDirector** on campaign elite/boss
- **Ascension** (+mutators per campaign win) and **codex achievements** with token rewards
- Evolution upgrades apply on deploy; synergy tags in evolution pick UI

## Open questions (post-V2)

1. **Pace target** — 15 vs 30 min full run?
2. **Art** — replace colony placeholders with authored tiles?
3. **Platform** — daily seed leaderboard UI polish?

## Archived pre-V2 docs

Moved to `docs/archive/`: `PHASE1_DECISIONS.md`, `MULTI_SQUAD_DESIGN.md`, `UI_UX_REVIEW.md`
