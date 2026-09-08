# Request: battle visual read (it has to look like a fight)

**Status:** product-owner directed visual contract. **Resolver + viewer slice implemented** on `cursor/mvp-two-worlds-engine-0600`: formation guide + individual LOS, bake `facing/state/z/aim`, diorama + dust, Y-axis billboards, **8-frame soldier run/shoot sheets** from baked march/rout/fire, traveling shots, brief hit flashes, even 1× playback with 0.25×–8× controls, sparse audio. No per-unit banners. Live World Conquest locks unchanged.  
**Branch:** `cursor/mvp-two-worlds-engine-0600`  
**Depends on:** [REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md](REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md) §6, skill `eoy-battle-resolve`  
**Does not change** live World Conquest locks (R1, F5, F6, A14, …). Two Worlds stays a separate mode.

**Principle:** **realism of what you see, not perfect realistic mechanics.**  
Auto-resolve can stay simple, deterministic, and cheap. The **replay must read as two armies meeting, forming up, and fighting.** A 10-second glance should never look like two mobs jogging to the far edge of a green rectangle.

---

## 0. What is wrong today (evidence)

Current authority (`rust/eon_engine/src/battle.rs`) and viewer (`BattleView.gd`):

| What happens | Why it looks fake |
|--------------|-------------------|
| If nobody is in **reach 2.0**, every soldier walks toward the **enemy centroid** | That is a chase, not a battle line. Spacing is ~1.9, so they must almost stack to “fight.” |
| After local enemies die, they resume walking toward whoever is left | Survivors / routers pull the centroid to the **far map edge**, so the winners **jog across the whole field** |
| Attack is invisible HP subtraction on cooldown | No halt, no facing, no shot, no recoil — contact looks like standing still, then people vanish |
| Snapshot is `{x, y, alive}` only | Viewer cannot pose walk / aim / fire / fall / flee |
| Sprites are spherical camera-facing billboards, one idle frame | Nobody aims at the enemy; the camera auto-rotates, so facing is unreadable anyway |
| Dead units scale to 0 | No bodies, no holes in the line, no “we held this ground” |
| Green unshaded plane, no front, no banners | Two colored stamps on a tennis court |

The written design already asked for **formation slots + local LOS**. The MVP skipped that and used centroid-seek. This doc is the visual bar that implementation has to hit.

---

## 0.5 Fight model (product-owner, 2026-09-07)

**Rust resolves the fight. The replay only plays it back.** Godot interpolates baked transforms, facing, and state. It does not pick targets, apply damage, or invent paths. Muzzle flashes and tracers are drawn **from** baked fire ticks, not from a second combat brain.

**Formation is a guide, not a rail.** The squad brain paints a moving *field*: facing, desired interval, engagement line, morale. Each body is an individual with its own HP, perception, and target. It is pulled toward its slot the way a soldier is pulled toward a company — then it **breaks the slot** to shoot, duck, lunge, or chase whoever is in front of it. A good fight looks like a **line made of people**, not chess pieces and not a mob.

Same loop for **everything that will ever show up**:

| Domain | Examples | Locomotion | How formation guides |
|--------|----------|------------|----------------------|
| Land | soldier, tank, zombie, alien | ground plane, terrain blockers | slot attractor + cohesion weight |
| Air | plane, bomber, flyer | altitude lane, passes | flight corridor / stack, not infantry files |
| Naval (later) | boat, landing craft | water plane | line-abreast / column on the wet |

Cohesion is a **number per kind**, not a different engine. Tanks hug the guide. Soldiers drift and fight. Zombies almost ignore the slot and swarm. Planes never share the infantry hash for “walk to file.” One resolver, many profiles.

Bodies **do not share a spot**: same-domain units keep personal space (`spacing`, infantry **3.6** vs 3.2 billboards). Infantry deploys as **regiments of 100**, bombers as **wings of 5** with looser files so the field reads as several units, not one blob.

Prototype art stays soldiers + bombers. The **data model** must not assume those are the only two kinds (kind id, domain, reach, cohesion, weapon).

---

## 1. What “effective battle” means here

A fight is **readable** when the eye can answer, without UI:

1. **Where is each army?** Two masses, own halves of the field, not mixed soup.
2. **Which way are they facing?** Toward the threat, not the camera.
3. **What phase is this?** Deploy / advance / contact / grind / break / hold.
4. **Where is the front?** A band of violence between two still-ish ranks, not a migrating blob.
5. **Who is shooting vs running?** Halted bodies spit fire; movers are marching or fleeing, not both at once.
6. **Who is winning?** One line thins and folds **backward**; the other **stays**.

If those six reads fail, more polygons will not save it.

---

## 2. The seven beats (must play in this order)

Every baked replay should be *stageable* as these beats. Skip none. Compress timing, do not skip structure.

### Beat 1 — Tableau (1–3 s of watch time)

Both armies **already formed** on their own ground. Ranks, depth, a gap of empty field between them. Camera can see **both** masses. Nothing is fighting yet.

This is the “two armies on a field” poster. If this beat is missing, the rest never reads as a battle.

### Beat 2 — Advance to contact

Bodies move **as a formation**, not as independent homing missiles.

- Shared facing toward the enemy line.
- Front rank leads; rear ranks keep interval.
- Speed is a march, not a sprint-to-centroid.
- The gap closes until **engagement range**, then **stops**.

Bombers (if present) are a **second layer** above / behind, not mixed into the infantry scramble.

### Beat 3 — Halt and present

The front **stops**. Weapons come up. A pause long enough to read “we are about to fire.”  
Melee-only troops may close the last few meters as a **charge** (short, committed, then stuck in a scrum). They do **not** keep jogging through the enemy and out the back.

### Beat 4 — Exchange (the actual fight)

This is the meat. It must look busy **in place**.

- A **kill zone** between the two fronts: muzzle flashes, **short traveling shots** (not a held beam), bomb puffs, occasional bomber pass.
- Individuals **face the nearest threat** (or the enemy line if none in LOS).
- Fire is **rhythmic**, not a continuous glow: volley or stutter, then recock. Shooter sprites stay their normal color; the muzzle burst is the tell.
- Hits **flash** the sprite briefly, then return to normal — they do not stay lit for the whole volley. They stagger or drop; neighbors do not instantly teleport.
- The line may **ripple** (dress ranks, step into a hole) but the **front stays a front**.

### Beat 5 — Attrition / local collapse

Holes open. A company folds. Dust and bodies mark where the fight **was**.  
When the other line **breaks**, the standing army **chases** — they do not hold the old front and wait.

### Beat 6 — Break

The losing side **turns away from the enemy** and runs toward **their own rear**, not through the winners and off the far side.

- Facing flips (backs to the foe, or panicked 3/4).
- Speed up; cohesion dies (gaps, stragglers).
- The army that is **not** routing **pursues**: they run after the fleeing backs, keep shooting, and try to cut them down. They do **not** idle on the engagement line while the other side jogs off the map.
- When a router hits the **home map rim**, it **phases out** (escaped / teleported away). That body is a **survivor**, not a corpse. The sim drops it so the fight does not idle at the tick cap.
- Chasers stop a few meters inside that rim so they do not pile on the wall.

### Beat 7 — Occupy the field

Camera leftover: pursuers where the last routers vanished, banners, bodies on the dirt.  
**Nobody should be stacked on the opposite map edge as a commute from the standing fight** — pursuit is a chase of fleeing troops, not a victory jog through empty grass.

---

## 3. Soldier visual language (the checklist)

These are presentation truths. Mechanics can fake them (longer visual reach, stop-at-range orders, baked anim flags).

### 3.1 Body and facing

- [x] **8-way facing preferred, 4-way minimum** relative to the *battlefield*, not the camera (already in the two-worlds request). Spherical billboards that always face the lens are a prototype crutch.
- [x] Walk cycle while moving; idle / aim while halted; fire / recoil on shot; hit react; death fall; rout run.
- [x] The sprite’s **weapon points at the enemy**, not at the viewer.
- [ ] Silhouette must read at 1000 units: hat / gun / color block. Tiny identical dots fail.

### 3.2 Positioning (the main bug)

- [ ] Each body has a **formation slot** as an *attractor* (rank × file, or an air corridor). They are biased toward it, not glued to it.
- [ ] Once a local enemy is in perception/LOS, **fighting that enemy wins over dressing ranks**. The line is allowed to get messy at the front.
- [ ] The squad still owns an **engagement line**. The *mass* stops there; individuals may step forward/back a few meters to shoot or melee.
- [ ] **Do not pass through** the enemy mass as a commute to the far edge. Local overlap / lunge is fine; percolating to the opposite baseline is not.
- [ ] After local kills, retarget the **nearest valid enemy in LOS**, not a leftover centroid **while both lines still stand**. If the other side is **routing**, pursue those routers across the field.

### 3.3 Firing (must be visible)

Soldiers in this fantasy are **armed troops**, not fists.

- [ ] Engagement range must be **obviously longer than personal space**. If they have to touch to “attack,” it will always look like a brawl-jog. Visual musket / rifle range can be a presentation reach even if damage math stays simple.
- [x] **Muzzle flash** (1–2 frames) on the fire tick.
- [x] **Tracer, smoke puff, or impact spark** on the line between shooter and target — cheap instanced quads are enough. The brain fills in “bullets” if the rhythm is right.
- [ ] Cadence: not everyone fires the same frame. Stagger within the rank (already have attack cooldown — **show it**).
- [ ] Recoil / kick pose so the body is not a static stamp while “fighting.”

### 3.4 Melee (if used)

- [ ] Only the **front rank** that has closed. Rear ranks wait or shoot over / around (even a fake “over” is fine).
- [ ] Clash is a **scrum at the contact line**, push-and-shove, not a percolation to the map border.

### 3.5 Death and wounds

- [x] Dead stay as **corpses or stains** for the rest of the replay (LOD: far = dark splat / decal; near = fallen sprite).
- [x] Dying is a **fall**, not a pop-out (`scale = 0`).
- [ ] A thinning rank with bodies in front reads as a fight; empty grass does not.

### 3.6 Morale

- [ ] Shake / waver before rout (optional but cheap: extra facing jitter).
- [ ] Rout = turn + run **home**. Hit the home map rim → phase out (escaped survivor). Clamp/escape in the **sim**, not only in the viewer.
- [ ] The standing army **chases** routers (run + shoot). Holding the old engagement line while they escape is a miss.

---

## 4. Formation and mass (what sells “army”)

Borrowed from how Total War / historical films cheat:

- [ ] **Rectangular ranks** at deploy (already started in layout). Keep them during the advance.
- [ ] **Depth**: at least 2–4 ranks so the army is a block, not a single-pixel skirmish line.
- [x] **Banners / flags / officer dots** every N files — the eye tracks 6 landmarks, not 800 hats.
- [x] **Dust, kicked dirt, or a faint haze** on the contact band (GPU particles or a scrolling noise strip). Mass without dust looks like chess.
- [ ] **Color blocks** stay separated until contact. Friendly and hostile should not marble until the front actually meets.
- [ ] Casualties create **ragged holes**; optional slow **dressing** (neighbors slide into gaps). Instant teleport-fill looks robotic.

Individual overlap is allowed (Dominions-ish) **until it destroys the silhouette of the line**. If the line turns into a pile, add spacing / slot pressure.

---

## 5. Battlefield as a place (diorama)

A fight needs **ground that explains itself**.

- [x] Province-themed slab (biome, a hill, a road, a treeline, a ruin, a river edge).
- [x] **A visible no-man’s-land** at start: empty dirt between the two deployments.
- [x] High ground / chokepoint as **dressing** even if the first resolver ignores it. The camera should have something to orbit besides sprites.
- [x] Scale cues: a wagon, a wall fragment, a lone tree. Without them, 3.2-unit sprites on the slab feel like stickers. Custom Battle slab is **1000×600** (5× the original 200×120) so 10k-body stress tests have room.
- [x] Light: a directional sun + slightly warm/cool sides so armies read left vs right. Unshaded identical lighting flattens everything.
- [x] Keep GameTheme HUD chrome **thin**; the diorama is the star (`eoy-ui-theme`).

---

## 6. Camera and staging

The camera is part of the lie that makes it look real.

- [ ] **Default framing:** three-quarter / slight overhead, **both armies in view**, contact band near screen center. Today’s near-overhead + auto-rotate fights this.
- [ ] Auto-rotate **off by default** during the fight (or only a tiny yaw). Turntable cinema hides facing and makes people look like they are skating.
- [ ] Free orbit / zoom stays (Dominions). Defaults should be **cinematic, not inspection**.
- [ ] Optional beat cuts (later): tableau wide → advance medium → contact closer. Not required for MVP if the default angle already shows the line.
- [ ] Never crop to one army so the other “appears” by running in from off-screen.

---

## 7. Timing (feel vs clock)

Mechanics can resolve in 1400 ticks. The **watch** should feel like a small action, not a commute.

- [x] Tableau is still.
- [x] Advance is the slow beat (most of the travel time lives here).
- [x] Exchange is longer than the approach once they have met — the current “walk forever because centroid moved” inverts this.
- [x] Break is fast.
- [x] Hold / occupy is a short button on the end, then UI can say resolved.

Playback speed controls (0.25× / 0.5× / 1× / 2× / 4× / 8×) stay. Default is **even 1×** — the viewer does not auto-slow the form-up or speed up the fight. **1× must already look like a fight**, not a corrected fast-forward of a broken sim.

---

## 8. Air (and later naval) — different guides, same tick

Do not put aircraft in the infantry brain. They share the resolver; they do not share files.

- [x] Altitude: clearly **above** the slab.
- [x] Paths: **overfly, drop, continue, turn, next pass** — not hovering gunships or taxiing through the soldier blob.
- [x] Attacks: **ground blast** (bomb puff / shock ring). Infantry small-arms vs aircraft are weak (~50 soldiers to confidently kill one bomber). Blast **launches** land bodies; they take damage and land elsewhere — not a guaranteed kill.
- [ ] If they “fight” other bombers, that is a high dogfight layer, not ground centroid-seek.

---

## 9. Authority vs presentation

Player still **does not micro** the battle. **All movement, targeting, hits, morale, and death happen in Rust.** The viewer is a projector.

Rust owns:

- Squad orders as **guides**: **AdvanceToLine**, **HoldAndFire**, **Charge**, **RoutHome**, **Pursue**.
- Per-body: cohesion toward slot, local LOS target, attack if in that kind’s weapon range, HP, rout.
- Kind profiles: domain (land/air/sea), cohesion, reach, speed, altitude.

The bake is the report (`facing`, `state`, position, optional `z`). Godot interpolates it and may spawn **purely cosmetic** muzzle flashes and **short traveling shot streaks** from fire ticks (not a shooter-to-target beam). Hit tint is a **brief flash**, not a held glow. If a unit did not fire in Rust, the viewer does not pretend it did.

Not allowed:

- GDScript re-resolving combat.
- “Looks better” by letting units clip through the enemy to the far baseline.
- Hiding the chase by clamping only in the viewer while the sim still jogs to the opposite edge (today’s rout clamp is a band-aid).

---

## 10. Replay bake contract (minimum)

`{x, y, alive}` is not enough. Per unit, per recorded frame (or delta):

| Field | Why |
|-------|-----|
| `x, y` | position |
| `facing` or `yaw` | 4/8-way sprite |
| `alive` | still in the fight |
| `state` | idle / march / aim / fire / hit / dead / rout / fled |
| optional `in_air` / `z` | bombers |

Corpses can freeze the last dead pose and stop updating.

---

## 11. Anti-patterns (do not ship)

- Seek **enemy centroid** as the movement goal **while both sides still stand**. After a break, pursuing the routing mass is required.
- Attack **reach ≈ body radius**.
- Instant delete on death.
- Camera-facing only sprites as the finished look.
- Whole army **occupying the enemy deployment** at the end.
- Mixing bombers into the ground blob.
- Auto-rotate as the default “cinematic.”
- UI text (“RESOLVED”, frame counter) doing the job the picture should do.

---

## 12. Acceptance (playtest)

Stand in the default camera at 1× with a few hundred soldiers. Pass only if:

1. You can pause in the first seconds and **photograph two formed armies with a gap**.
2. They **march together**, then **stop** and **face** each other.
3. You can see **shots** (flash and/or tracer) without opening a debug overlay.
4. The fight **stays on a front** in the middle third of the field.
5. When one side breaks, they run **home**; the other side **chases them down** (does not wait on the old front). Routers that reach the rim phase out.
6. Afterward the field is **occupied**, with bodies, not empty grass and two idle piles.

Headless goldens should assert **phase geometry** (median X of living attackers stays on their side until contact; after break, routers’ X moves toward own baseline; the standing army’s median X moves after them). Cosmetic FX may be drawn in the viewer only if they match baked fire/death ticks.

---

## 13. Out of scope (this pass)

- Player-controlled units in battle.
- Perfect ballistics, cover simulation, or IK.
- Full unique animations / art for tanks, zombies, aliens, naval (soldiers + bombers first). The **kind/domain/cohesion** fields must exist so those bodies can drop in later.
- Changing live World Conquest combat.
- New design locks for the real-time globe mode.

---

## 14. Suggested build order

1. **Stop the commute** — squad engagement line + hold-and-fire; kill centroid-seek after contact; rout toward own baseline in sim.
2. **Bake state + facing** — even with the current single sprite, a 4-way flip and a flash quad change the read.
3. **Corpses stay.**
4. **Camera default** that shows both lines; auto-rotate off.
5. **Diorama dressing** + dust.
6. **Walk / fire frames** — 8-frame soldier sheets (`ST_MARCH`/`ST_ROUT` run, `ST_FIRE` shoot); 8-way unique art when budget allows.

Items 1–4 are the difference between “RTS leak” and “a battle.” 5–6 make it handsome.
