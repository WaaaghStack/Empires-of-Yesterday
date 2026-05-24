# Empires of Yesterday

Xenopurge-style 2D real-time tactical command prototype with a **planet reclamation run loop** (Godot 4.6+).

Each planet run generates a **single persistent 18–24 room hull** with corridors, doors, fog of war, **1–2 nest hives**, evolution nodes, and an Overmind finale.

## How to play — Planet Reclamation (primary)

1. **Main Menu** → **New Planet Run** (or **Daily Seed Run**).
2. **Orbital Carrier** — configure each squad:
   - **Loadout preset** (kinetic / energy / fire / bio tags)
   - **Pilot traits** (Steady, Reckless, Hive-Hater, etc.)
   - **Drop sector** (north / south / east / west)
   - **Squad stance** (Aggressive / Balanced / Cautious)
   - **Optional mutators** (Quiet Deck, Accelerated Swarm, Reinforced)
3. **Launch Planet Reclamation** → `PlanetMission` tactical map.
4. Carrier drop zones auto-assign deploy rooms per sector (or pick manually).
5. Press **BEGIN MISSION** — combat runs **in real time** (no global pause).
6. **SPACE** toggles the **Sector Delegation** overlay (assign sectors / doctrines while combat continues).
7. **Orbital bar** (bottom, planet runs): Scan / Strike / Resupply / EMP (costs orbital charge, usable during combat).
8. Purge **1–2 nest hives** → phases escalate → **Overmind awakens** → destroy queen → **evac opens**.
9. Extract all living operators when ready (no time limit).
10. **Run Summary** shows Imperial Reclamation rank, biomass, echoes, and evolution build.

## Commander controls

- **F1 / F2 / F3** — select Alpha / Bravo / Charlie
- **O** objective doctrine, **S** search & destroy, **E** extract, **Space** sector overlay
- **Comms tab** defaults to **Priority** (Alerts + Objective)
- Minimap bottom-left shows hive / extract / evolution icons
- Squad tab shows sector, doctrine, HP%, and status per squad

## Legacy 4-op run (optional)

Main Menu → **More…** → **Legacy 4-op run** → Squad Select → discrete ops with Between-Op Hub.

## Headless QA

```bash
godot --headless --path . res://qa_runner.tscn
```

Exit code `0` = pass; report at `qa_report.txt`. Logs write to `logs/`.

See `EMPIRE_VISION.md` for the north-star checklist and `V2_ROADMAP.md` for shipped V2 scope.
