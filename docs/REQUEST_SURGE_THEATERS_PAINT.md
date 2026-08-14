# Request: outpost modes, named theaters, and unit paint

**Status:** planned (branch `feat/surge-theaters-paint`)  
**Does not ship on this branch until implemented.** Live Play stays R1 (instant place, ferry, no roads/bridges) until each item lands.

Three player-facing features. Win formula stays **land conquest or zero enemy pressure**; units still do not change it (F5). Roads and land bridges stay gone (R1).

| # | Feature | Player verb |
|---|---------|-------------|
| 1 | Outpost modes | Pump / Drain / Battery+Surge on a placed outpost |
| 2 | Named theaters | Pangea / Archipelago / Earth as first-class map starts |
| 3 | Unit paint | One rally pin: beachhead (soldiers) or strike (bombers) |

---

## 1. Outpost modes (pump / drain / surge)

### Why

Every outpost is the same trickle inject today. After R1 there is no logistics puzzle; the next decision has to live on the building itself.

### Modes

Same outpost kind, three modes. Placement cost and spacing unchanged (400 Supply, min 6 cells). Mode is chosen after place (cycle on the selected outpost) or at arm-time if that stays cheap in HUD.

| Mode | Inject | Feel |
|------|--------|------|
| **Pump** | Current behavior: periodic inject onto neighboring claimable tiles at spawn rate. | Default. Thin film, slow creep. |
| **Drain** | Pulls enemy pressure from neighbors into cancellation / toward this tile instead of adding friendly inject. | Hold a pass; starve a film. |
| **Battery** | Tap off. The inject that would have gone onto the map accrues in a **tank on this structure** (not a map-tile reservoir). Overlay depth at the outpost swells while charging. | Save a wave. |

**Surge** is emptying a Battery tank in one shot onto the same neighbor tiles Pump would have fed.

- Height jumps; gradient flow shoves a thick slug downhill in a couple of seconds.
- A slug can crest a ridge a trickle never would (`H = pressure + elevation`).
- On contact, cancellation eats both films. Overstored vs their line = punch through. Understored = nibble.
- After fire, tank is empty. Outpost stays in Battery (recharge) or the player flips to Pump.
- **Manual trigger only** (click charged outpost / Surge with it selected). Auto-fire at full is just a delayed drip.

### Failure / combo (intentional)

- Enemy takes the outpost tile → tank is lost (or dumps as their pressure — pick one in implementation and lock it; default **lost**).
- Surge into a deep enemy basin → wave dies in cancellation.
- Two Batteries on ridges that fire into the same valley **add**.

Surge is still pressure, so it can help conquest or zero-power. It is not a unit ability.

### Out of scope for this item

New structure kinds, tech unlocks, auto-surge last-stand (that was a separate match-shape idea).

---

## 2. Named theaters (Pangea / Archipelago / Earth)

### Why

Custom World already has `procedural`, `land_bias`, `mountain_bias`, `resource_density`. Players should not have to invent a war by dragging sliders. Three named starts, same rules, different match texture.

| Theater | Land | What the match is about |
|---------|------|-------------------------|
| **Earth** | Default Earth mask (today’s Play) | Real coasts; ferry when you leave the continent. |
| **Pangea** | Procedural, high land / low ocean | One land war. Outpost placement and basins dominate; ferry is rare. |
| **Archipelago** | Procedural, low land / high ocean | Ferry + bombers *are* the game. Beachhead paint matters. |

Exact `land_bias` / `mountain_bias` numbers are implementation; lock them in `WorldConquestConfig` / catalog so Earth / Pangea / Archipelago are stable across seeds (seed still varies continents for the two procedural theaters).

### UX

Main Menu (and Custom World) expose theater as a choice, not a hidden criteria blob. Custom sliders remain for people who want them; picking a theater fills criteria then Generate & Play.

**Same Map** keeps the theater + seed. **Play Again** keeps theater, new seed.

### Out of scope

New biomes, extra resource types, per-theater unique buildings.

---

## 3. Beachhead + strike paint

### Why

Soldiers and bombers already auto-hunt. Paint answers “go here” with **one pin**, not an RTS command card. Units still do not change the win formula (F5).

One rally at a time per side. Latest click wins. No queues, no waypoints. Pin clears when its job is done or the player cancels / paints elsewhere.

### Beachhead paint (soldiers)

Uses existing ferry + `extend_beachhead_from_landing`.

1. Idle / eligible soldiers path toward the painted **coast** (water at `SOLDIER_FERRY_MOVE_MULT` 0.25×).
2. First boots on that land open the contiguous landmass (existing beachhead flood). Claimable is shared — the door is not team-locked.
3. **Hold the landing.** Do not immediately repath to another continent. Keep aura + erode on that mass so a puddle exists for an outpost.
4. **Release** when: the player owns enough of the mass to place, they paint a new coast, or they cancel. Then resume normal front-hunt.

Soldiers do not garrison forever. Five infantry cannot occupy a continent; that is the outpost. If the player never places, the puddle dies to upkeep or enemy cancel.

Pressure still does not cross ocean. Opening claimable does not let the capital flood the island. Arrival is the door-kick; **Pump / Surge / a local outpost** is occupation.

### Strike paint (bombers)

Uses existing bomb: `open_claimable_for_air_strike` on the struck cell, enemy pressure `− bomb_power`, friendly splash `+ 0.35 × bomb_power`.

1. Bombers fly to the marked **cell** (not ferry-gated).
2. Bomb on arrival (same numbers as now).
3. Keep that cell as the goal until it flips to the painting team, or cancel / repaint. Extra bombers peel to **neighbors** of the pin (small crater, not a stack on one tile).
4. **Release** when the painted cell and that tiny crater are owned. Resume auto-hunt. No CAP orbit.

Air does not hold ground. Follow up with an outpost, soldiers, or a Surge into the hole, or the stain fades.

### After units arrive (player’s next click)

| You marked | Units arrive | You still need |
|------------|--------------|----------------|
| A coast | Door opens + a puddle | Outpost on that mass, or the puddle dies |
| A pass / deposit / island tile | Hole + stain | Surge into the hole, soldiers onto the stain, or another outpost |

Paint without follow-up is a spent ferry / bomb interval.

### Out of scope

Click-to-move armies, per-unit orders, hero units, paint that captures tiles by itself.

---

## Design locks this work must not break

| Lock | Keep |
|------|------|
| **F5** | Win is land or zero pressure. Paint and surge do not add a unit-kill victory. |
| **F6** | Caps stay 5 per barracks/hangar, 100 global each. Paint does not raise caps. |
| **R1** | No roads, no land bridges. |
| **R2** | Ferry water speed stays 0.25× unless this work explicitly retunes it. |
| **A14** | Bombers still have no continuous mineral upkeep. |

---

## Suggested implement order

1. **Theaters** — criteria presets + menu; no sim change. Unlocks Archipelago as the paint testbed.
2. **Paint** — rally pin + hold/release on existing soldier/bomber brains.
3. **Outpost modes** — Battery tank + Surge inject; Drain last (needs a clear cancel-vs-siphon rule in Rust inject).

AI vs AI / `EnemyStrategy` should eventually pick modes and paint; not required for the first playable slice (player-only modes + paint is enough to feel the verbs).
