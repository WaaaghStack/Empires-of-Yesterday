# Phase 1 Architecture Decisions

*Updated May 23, 2026 — procedural maps + deploy-room selection*

---

## Map System (current direction)

**Decision:** Procedurally generate a new facility layout every mission. Rooms are stitched together automatically with L-shaped corridors, doors, and a runtime path graph.

**Why this replaced the static ship deck art:**
- Replayability — each run gets a different room graph and layout
- Spawn choice — players pick a **secure deploy room** at mission start (rooms with no pre-placed hostiles)
- The old reference JPEG (`assets/maps/ship_interior_reference.jpg`) is **deprecated** for gameplay; visuals are schematic (corridor polygons + hull outline)

**Generation pipeline (`ProceduralMapGenerator.gd`):**
1. Roll seed → 8–10 rooms on a jittered grid
2. Connect rooms with a **minimum spanning tree** + 2 loop edges (non-linear paths)
3. Stamp **L-corridors** between linked rooms
4. Assign roles:
   - **3 hostile objective rooms** (1–2 enemies each, not spawn-eligible)
   - **1 extraction room** (Command Bridge, furthest slot)
   - **Remaining rooms = secure** (spawn-eligible, no enemies)
5. Build `DynamicPathGraph` (room nodes + junction nodes + doors)

**Runtime data:** `MissionMapData` holds rooms, corridors, hull bounds, and path graph for the active mission.

---

## Room & movement model (unchanged core)

- **Area2D rooms** carry metadata (name, objectives, fog state, spawn flags)
- **Corridor waypoint movement** via `DynamicPathGraph` (A* on stitched graph)
- **Doors** block movement and line-of-sight until opened
- **Fog of war** — unrevealed rooms hidden; enemies invisible until spotted

---

## Mission flow (Version One)

1. **Squad Selection** — pick up to 4 marines  
2. **Tactical Map load** — procedural facility generated (seed logged)  
3. **Deploy room selection** — click a **green secure room** (left-click); hostile rooms are red  
4. **BEGIN MISSION** — squad spawns in chosen room, fog activates  
5. **Orders** — Move / Clear / Search & Destroy (autonomous) / Defend / **Explore [X]** / Extract  
6. **Win** — clear objectives → extract at Command Bridge  
7. **Debrief** → hub heal/modifier → next op (run loop)

## Explore [X]

**Decision:** Explore is an autonomous sweep order (like S&D). Select operator(s), press **Explore [X]** or the Explore button — they path through uncharted sectors until all are searched. Required for Silent Extract ops (evac hidden until 2 rooms searched) and for locating Command Bridge under fog.

---

## Roguelite run loop (May 2026)

- **RunState** autoload — 4 ops per run, squad HP/KIA carries over
- **MissionDebrief** — stats, seed, run credits
- **BetweenMissionHub** — heal 25% HP for run credits, pick op modifier
- **SaveManager** — Command Tokens, class/portrait unlocks in `user://profile.save`
- **MainMenu** entry — daily seed uses date hash

---

## Search & Destroy

**Decision:** S&D is a **set-and-forget** order. Press **S** (or S&D button) with a marine selected; they autonomously sweep the deck until **all hostiles are eliminated**.

---

## Future work (Phase 2+)

| Area | Idea |
|------|------|
| Layout | Room shape templates, branch caps, biome themes |
| Visuals | TileMap / modular art overlaid on procedural graph |
| Intel | Seed sharing, daily challenge seeds |
| Multi-squad | Multiple deploy zones, simultaneous S&D |
| Static maps | Optional handcrafted missions alongside procedural |

---

## Deprecated / legacy

| Item | Status |
|------|--------|
| `ShipMapConfig.gd` static room list | Legacy reference; runtime uses `MissionMapData` |
| `ShipPathGraph.gd` static graph | Legacy reference; runtime uses `DynamicPathGraph` |
| Ship interior JPEG | Visual reference only; not loaded at runtime |

---

*Document originally created during Phase 1 start — May 23, 2026*
