# Empires of Yesterday

Xenopurge-style 2D real-time tactical command prototype with a **hybrid roguelite run loop** (Godot 4.6+).

Each operation generates a **random facility layout** — rooms auto-stitch with corridors, doors, fog of war, and (on medium/large decks) **bio-hives**.

## How to play

1. **Main Menu** — New Run, Continue, Daily Seed Run, or Codex.
2. **Squad Select** — review **3 squads** (Alpha, Bravo, Charlie). Each squad rolls **4 random operators** from your unlocked classes; use **Reroll Squad** or **Reroll All** if you want a new draw, then **Start Run**.
3. **Tactical Map** — assign **deploy room per squad** (Alpha → Bravo → Charlie), then **BEGIN MISSION**.
4. The game starts **paused** — select a squad (**F1 / F2 / F3**) or individual operator (click / keys **1–4**).
5. Issue orders:
   - **Objective [O]** — auto doctrine from mission template (S&D, Explore, Defend, etc.)
   - **Search & Destroy [S]** — coordinated purge via shared task board
   - **Move / Clear / Defend / Extract** — **M / C / D / E**, then right-click a room
   - **Explore [X]** — autonomous sweep of uncharted sectors
6. Press **Space** to unpause and watch squads execute.
7. Clear objectives (including **hives** on `hive_purge` ops), then extract at **Command Bridge**.
8. **Minimap** (bottom-left) shows squads, rooms, and threat overlay when hives activate.
9. After each op: **Mission Debrief** → **Between-Op Hub** → next op (4 ops per run).

## Multi-squad commander UI

- Left panel: **3 squad cards** (aggregate HP, doctrine, status) — click to select squad.
- Comms filters: **All / Alerts / Combat / Objective**.
- Right panel: **commander HUD** when a full squad is selected.

## Headless QA

```bash
godot --headless --path . res://qa_runner.tscn
```

Exit code `0` = pass; report at `qa_report.txt`. See `MULTI_SQUAD_DESIGN.md` for expansion details.
