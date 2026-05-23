# Empires of Yesterday

Xenopurge-style 2D real-time tactical command prototype (Godot 4.3+).

Each mission generates a **random facility layout** — rooms auto-stitch with corridors, doors, and fog of war.

## How to play

1. Select up to 4 marines on the squad screen and **Deploy**.
2. On the tactical map, **click a secure room** (green outline) to choose your deploy site. Hostile sectors are marked in red and cannot be chosen.
3. Press **BEGIN MISSION**.
4. The game starts **paused** — select a marine (click or keys **1–4**).
5. Issue orders:
   - **Move / Clear / Defend / Extract** — **M / C / D / E**, then right-click a room
   - **Search & Destroy** — **S** (set-and-forget; marine purges the deck until all hostiles are dead)
6. Press **Space** to unpause and watch your squad execute.
7. Clear all marked objectives, then extract at **Command Bridge** to win.
8. Press **R** for the selected marine's class ability.

## Fog of war

- Rooms start hidden except your deploy room.
- Enemies are invisible until a marine has **line of sight**.
- Closed bulkheads block sight and movement.

## Classes

- **Assault** — balanced frontline fighter (Adrenaline)
- **Support** — squad healing (Field Repair)
- **Marksman** — long-range damage (Focus Fire)
- **Breacher** — room-clearing burst (Breaching Charge)

## Procedural maps

Every run rolls a new seed (shown in the comms log). Room count, connections, and hostile placement change each mission. See `PHASE1_DECISIONS.md` for design details.
