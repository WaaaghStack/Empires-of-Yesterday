//! GDExtension surface for the proposed two-worlds transaction engine (`eon_engine`).
//!
//! Thin Godot wrapper over the godot-agnostic authority core. Holds a persistent campaign
//! (`World` + `Ledger`) so Godot can drive a turn-based match: start a campaign, end turns, read
//! back the wide-row report (provinces / factions / armies), and pull baked battle-replay frames
//! for the battle viewer. The heavy lifting lives in `eon_engine` and is unit-tested there.
//!
//! Status: exploratory MVP (docs/REQUEST_TWO_WORLDS_TRANSACTION_ENGINE.md). Additive/opt-in — it
//! does not touch the live World Conquest path.

use eon_engine::battle::{
    resolve_battle_in_province, resolve_battle_with_plan, BattleOrder, BattlePlan, BattleReport,
    FormationKind, SquadDeploy, BATTLE_HEIGHT, BATTLE_WIDTH, HILL_BLOCK_R, HILL_CX, HILL_CY, HILL_R,
    MAX_BATTLE_UNITS, RUIN_CX, RUIN_CY, RUIN_R, RIVER_X,
};
use eon_engine::model::{FactionId, GemPath, Squad, UnitKind};
use eon_engine::{
    run_ai_vs_ai_batch, run_headless_demo, scenario, turn::run_turn, Ledger, Outcome, TurnReport,
    World,
};
use godot::prelude::*;

type Dict = Dictionary<Variant, Variant>;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct TwoWorldsEngine {
    base: Base<RefCounted>,
    world: Option<World>,
    ledger: Option<Ledger>,
    last_report: Option<TurnReport>,
    last_outcome: String,
    /// Battles available for the viewer — set from the last turn or a custom battle.
    battles: Vec<BattleReport>,
}

#[godot_api]
impl TwoWorldsEngine {
    // ---- headless helpers (also used by tests / smoke) -------------------------------------
    #[func]
    fn run_demo(&self, seed: i64, turns: i64) -> GString {
        GString::from(run_headless_demo(seed as u64, turns.max(0) as u32).as_str())
    }

    #[func]
    fn self_check(&self) -> GString {
        let a = run_headless_demo(1234, 30);
        let b = run_headless_demo(1234, 30);
        let text = format!(
            "two_worlds self_check: deterministic={} reconciled={}\n{a}",
            a == b,
            !a.contains("RECONCILE FAILURE"),
        );
        GString::from(text.as_str())
    }

    #[func]
    fn run_ai_vs_ai_batch(&self, count: i64, max_turns: i64) -> GString {
        GString::from(run_ai_vs_ai_batch(count.max(0) as u32, max_turns.max(1) as u32).as_str())
    }

    // ---- persistent playable campaign ------------------------------------------------------

    /// Start (or restart) a turn-based campaign from `seed`. Uses the seed-varied procedural ring.
    #[func]
    fn new_campaign(&mut self, seed: i64) {
        let (w, l) = scenario::procedural_world(seed as u64);
        self.world = Some(w);
        self.ledger = Some(l);
        self.last_report = None;
        self.last_outcome = "Ongoing".into();
    }

    /// Start a campaign from a province partition carved by the presentation (the 3D globe).
    /// `neighbors` is an Array of PackedInt32Array (per-province adjacency). `capital_of` and
    /// `deposit` are PackedInt32Array (-1 = none), `has_throne` a PackedByteArray (0/1).
    #[func]
    fn begin_campaign(
        &mut self,
        seed: i64,
        faction_count: i64,
        neighbors: Array<Variant>,
        capital_of: PackedInt32Array,
        has_throne: PackedByteArray,
        deposit: PackedInt32Array,
        army_soldiers: i64,
        army_bombers: i64,
    ) {
        let mut nb: Vec<Vec<u32>> = Vec::new();
        for v in neighbors.iter_shared() {
            let list = v.try_to::<PackedInt32Array>().unwrap_or_default();
            nb.push(list.to_vec().into_iter().map(|x| x.max(0) as u32).collect());
        }
        let caps: Vec<i32> = capital_of.to_vec();
        let thr: Vec<bool> = has_throne.to_vec().into_iter().map(|b| b != 0).collect();
        let dep: Vec<i32> = deposit.to_vec();
        let (w, l) = scenario::from_partition(
            seed as u64,
            faction_count.max(2) as usize,
            nb,
            caps,
            thr,
            dep,
            army_soldiers.max(0) as u32,
            army_bombers.max(0) as u32,
        );
        self.world = Some(w);
        self.ledger = Some(l);
        self.last_report = None;
        self.last_outcome = "Ongoing".into();
    }

    #[func]
    fn is_active(&self) -> bool {
        self.world.is_some()
    }

    #[func]
    fn current_turn(&self) -> i64 {
        self.world.as_ref().map(|w| w.turn as i64).unwrap_or(0)
    }

    #[func]
    fn outcome(&self) -> GString {
        GString::from(self.last_outcome.as_str())
    }

    /// Advance one turn. Returns a summary dict: { turn, outcome, done, battles: [ {..} ] }.
    /// Battle frames are fetched separately via `get_last_battle_frames`.
    #[func]
    fn end_turn(&mut self) -> Dict {
        let mut out = Dict::new();
        let (world, ledger) = match (self.world.as_mut(), self.ledger.as_mut()) {
            (Some(w), Some(l)) => (w, l),
            _ => {
                out.set("error", &GString::from("no active campaign"));
                return out;
            }
        };
        let report = run_turn(world, ledger);
        self.last_outcome = format!("{:?}", report.outcome);
        out.set("turn", report.turn as i64);
        out.set("outcome", &GString::from(self.last_outcome.as_str()));
        out.set("done", !matches!(report.outcome, Outcome::Ongoing));

        let mut battles = Array::<Variant>::new();
        for b in &report.battles {
            let mut bd = Dict::new();
            bd.set("province", b.province as i64);
            bd.set("attacker", b.attacker as i64);
            bd.set("defender", b.defender as i64);
            bd.set("winner", b.winner.map(|w| w as i64).unwrap_or(-1));
            bd.set("ticks", b.ticks as i64);
            bd.set("owner_before", b.owner_before.map(|w| w as i64).unwrap_or(-1));
            bd.set("owner_after", b.owner_after.map(|w| w as i64).unwrap_or(-1));
            bd.set("elevation", b.elevation as i64);
            let mut cas = PackedInt32Array::new();
            for (_, c) in &b.casualties {
                cas.push(*c as i32);
            }
            bd.set("casualties", &cas);
            battles.push(&bd.to_variant());
        }
        out.set("battles", &battles);
        self.battles = report.battles.clone();
        self.last_report = Some(report);
        out
    }

    /// Resolve a single standalone battle (Custom Battle testing tool). Stores it as the current
    /// battle so the viewer can stream frames. Returns a summary dict.
    #[func]
    fn resolve_custom_battle(
        &mut self,
        seed: i64,
        f0_soldiers: i64,
        f0_bombers: i64,
        f1_soldiers: i64,
        f1_bombers: i64,
    ) -> Dict {
        let (mut w, mut l) = scenario::duel_line(3, seed as u64);
        let s = w.seed;
        let mk = |sol: i64, bom: i64| -> Vec<Squad> {
            let mut v = Vec::new();
            if sol > 0 {
                v.extend(Squad { kind: UnitKind::Soldier, count: sol as u32 }.into_regiments());
            }
            if bom > 0 {
                v.extend(Squad { kind: UnitKind::Bomber, count: bom as u32 }.into_regiments());
            }
            v
        };
        scenario::recruit_army(&mut w, &mut l, 0, 1, mk(f0_soldiers, f0_bombers));
        scenario::recruit_army(&mut w, &mut l, 1, 1, mk(f1_soldiers, f1_bombers));
        let report = resolve_battle_in_province(&mut w, &mut l, 1, 0, 1, s);
        self.store_custom_report(report)
    }

    /// Custom Battle with a roster of placed regiments and per-regiment march orders.
    /// Packed arrays are parallel (one slot per regiment). `orders` is per regiment; if it is
    /// empty or the wrong length, `order0` / `order1` fill in as that side's default.
    #[func]
    fn resolve_custom_battle_plan(
        &mut self,
        seed: i64,
        order0: i64,
        order1: i64,
        fac: PackedByteArray,
        kind: PackedByteArray,
        count: PackedInt32Array,
        x: PackedFloat32Array,
        y: PackedFloat32Array,
        facing: PackedFloat32Array,
        formation: PackedByteArray,
        orders: PackedByteArray,
    ) -> Dict {
        let n = fac.len();
        if n == 0
            || kind.len() != n
            || count.len() != n
            || x.len() != n
            || y.len() != n
            || facing.len() != n
            || formation.len() != n
        {
            let mut out = Dict::new();
            out.set("error", &GString::from("roster arrays misaligned"));
            return out;
        }
        let (mut w, mut l) = scenario::duel_line(3, seed as u64);
        let s = w.seed;
        let fac_v = fac.to_vec();
        let kind_v = kind.to_vec();
        let count_v = count.to_vec();
        let x_v = x.to_vec();
        let y_v = y.to_vec();
        let facing_v = facing.to_vec();
        let form_v = formation.to_vec();
        let order_v = orders.to_vec();
        let side_default = |fac_i: u8| -> BattleOrder {
            if fac_i == 0 {
                BattleOrder::from_u8(order0.clamp(0, 3) as u8)
            } else {
                BattleOrder::from_u8(order1.max(0).clamp(0, 3) as u8)
            }
        };
        let mut remaining = MAX_BATTLE_UNITS;
        let mut s0: Vec<Squad> = Vec::new();
        let mut d0: Vec<SquadDeploy> = Vec::new();
        let mut s1: Vec<Squad> = Vec::new();
        let mut d1: Vec<SquadDeploy> = Vec::new();
        for i in 0..n {
            let k = if kind_v[i] == 1 {
                UnitKind::Bomber
            } else {
                UnitKind::Soldier
            };
            let c = (count_v[i].max(0) as u32).min(remaining);
            if c == 0 {
                continue;
            }
            let ord = if order_v.len() == n {
                BattleOrder::from_u8(order_v[i])
            } else {
                side_default(fac_v[i])
            };
            let deploy = SquadDeploy {
                x: x_v[i],
                y: y_v[i],
                facing: facing_v[i],
                formation: FormationKind::from_u8(form_v[i]),
                order: ord,
            };
            for part in (Squad { kind: k, count: c }).into_regiments() {
                if remaining == 0 {
                    break;
                }
                let npart = part.count.min(remaining);
                remaining = remaining.saturating_sub(npart);
                let sq = Squad {
                    kind: part.kind,
                    count: npart,
                };
                if fac_v[i] == 0 {
                    s0.push(sq);
                    d0.push(deploy);
                } else {
                    s1.push(sq);
                    d1.push(deploy);
                }
            }
        }
        scenario::recruit_army(&mut w, &mut l, 0, 1, s0);
        scenario::recruit_army(&mut w, &mut l, 1, 1, s1);
        let mut deploys = d0;
        deploys.extend(d1);
        let plan = BattlePlan {
            order_a: BattleOrder::from_u8(order0.clamp(0, 3) as u8),
            order_d: BattleOrder::from_u8(order1.max(0).clamp(0, 3) as u8),
            deploys,
        };
        let report = resolve_battle_with_plan(&mut w, &mut l, 1, 0, 1, s, Some(&plan));
        self.store_custom_report(report)
    }

    /// Static per-unit data for a battle (constant across frames): counts + faction/kind arrays,
    /// plus battlefield dims and frame count. Fetch once, then stream frames.
    #[func]
    fn get_last_battle_meta(&self, index: i64) -> Dict {
        let mut out = Dict::new();
        out.set("width", BATTLE_WIDTH);
        out.set("height", BATTLE_HEIGHT);
        out.set("frame_count", 0);
        out.set("unit_count", 0);
        let Some(b) = self.battles.get(index.max(0) as usize) else {
            return out;
        };
        out.set("frame_count", b.frames.len() as i64);
        out.set("province", b.province as i64);
        out.set("attacker", b.attacker as i64);
        out.set("defender", b.defender as i64);
        out.set("winner", b.winner.map(|w| w as i64).unwrap_or(-1));
        out.set("elevation", b.elevation as i64);
        out.set("owner_before", b.owner_before.map(|w| w as i64).unwrap_or(-1));
        out.set("owner_after", b.owner_after.map(|w| w as i64).unwrap_or(-1));
        out.set("river_x", RIVER_X);
        out.set("hill_x", HILL_CX);
        out.set("hill_y", HILL_CY);
        out.set("hill_r", HILL_R);
        out.set("hill_block_r", HILL_BLOCK_R);
        out.set("ruin_x", RUIN_CX);
        out.set("ruin_y", RUIN_CY);
        out.set("ruin_r", RUIN_R);
        let mut fac = PackedByteArray::new();
        let mut kind = PackedByteArray::new();
        if let Some(f0) = b.frames.first() {
            for u in &f0.units {
                fac.push(u.faction as u8);
                kind.push(match u.kind {
                    UnitKind::Soldier => 0,
                    UnitKind::Bomber => 1,
                });
            }
        }
        out.set("unit_count", fac.len() as i64);
        out.set("fac", &fac);
        out.set("kind", &kind);
        out
    }

    /// Per-frame tracks: x/y/z, alive, facing (8-way octant),
    /// state (idle/march/aim/fire/dead/rout/fled/hit), aim_x/aim_y on fire.
    /// Fled = escaped at the rim; still alive.
    #[func]
    fn get_last_battle_frame_xy(&self, index: i64, frame: i64) -> Dict {
        let mut out = Dict::new();
        let mut xs = PackedFloat32Array::new();
        let mut ys = PackedFloat32Array::new();
        let mut zs = PackedFloat32Array::new();
        let mut alive = PackedByteArray::new();
        let mut facing = PackedByteArray::new();
        let mut state = PackedByteArray::new();
        let mut ax = PackedFloat32Array::new();
        let mut ay = PackedFloat32Array::new();
        if let Some(b) = self.battles.get(index.max(0) as usize) {
            if let Some(f) = b.frames.get(frame.max(0) as usize) {
                for u in &f.units {
                    xs.push(u.x);
                    ys.push(u.y);
                    zs.push(u.z);
                    alive.push(if u.alive { 1 } else { 0 });
                    facing.push(u.facing);
                    state.push(u.state);
                    ax.push(u.aim_x);
                    ay.push(u.aim_y);
                }
            }
        }
        out.set("x", &xs);
        out.set("y", &ys);
        out.set("z", &zs);
        out.set("alive", &alive);
        out.set("facing", &facing);
        out.set("state", &state);
        out.set("aim_x", &ax);
        out.set("aim_y", &ay);
        out
    }

    /// Provinces for rendering: id, owner (-1 none), dom per faction, unrest, throne, deposit
    /// (-1 none else gem index), capital_of (-1 none), neighbors.
    #[func]
    fn get_provinces(&self) -> Array<Variant> {
        let mut arr = Array::<Variant>::new();
        let Some(world) = self.world.as_ref() else {
            return arr;
        };
        for p in &world.provinces {
            let mut d = Dict::new();
            d.set("id", p.id as i64);
            d.set("is_land", p.is_land);
            d.set("elevation", p.elevation as i64);
            d.set("unrest", p.unrest);
            d.set("has_throne", p.has_throne);
            d.set(
                "owner",
                p.owner(&world.cfg).map(|f| f as i64).unwrap_or(-1),
            );
            d.set(
                "capital_of",
                p.capital_of.map(|f| f as i64).unwrap_or(-1),
            );
            d.set(
                "deposit",
                p.deposit.map(|g| g as i64).unwrap_or(-1),
            );
            let mut dom = PackedFloat32Array::new();
            for v in &p.dom {
                dom.push(*v);
            }
            d.set("dom", &dom);
            let mut nb = PackedInt32Array::new();
            for n in &p.neighbors {
                nb.push(*n as i32);
            }
            d.set("neighbors", &nb);
            arr.push(&d.to_variant());
        }
        arr
    }

    /// Factions for the status panel.
    #[func]
    fn get_factions(&self) -> Array<Variant> {
        let mut arr = Array::<Variant>::new();
        let (Some(world), Some(ledger)) = (self.world.as_ref(), self.ledger.as_ref()) else {
            return arr;
        };
        for (i, f) in world.factions.iter().enumerate() {
            let fid = i as FactionId;
            let mut d = Dict::new();
            d.set("id", fid as i64);
            d.set("name", &GString::from(f.name.as_str()));
            d.set("dominion", world.total_dominion(fid));
            d.set("land", world.owned_land(fid) as i64);
            let units: i64 = world
                .armies
                .iter()
                .filter(|a| a.faction == fid)
                .map(|a| a.total_units() as i64)
                .sum();
            d.set("units", units);
            d.set("thrones", world.owned_thrones(fid) as i64);
            d.set("alive", f.alive);
            let mut gems = PackedFloat32Array::new();
            for path in GemPath::all() {
                gems.push(ledger.balance(eon_engine::Account::Gems(fid, path)) as f32);
            }
            d.set("gems", &gems);
            arr.push(&d.to_variant());
        }
        arr
    }

    /// Armies (for map troop markers): faction, province, units.
    #[func]
    fn get_armies(&self) -> Array<Variant> {
        let mut arr = Array::<Variant>::new();
        let Some(world) = self.world.as_ref() else {
            return arr;
        };
        for a in &world.armies {
            let mut d = Dict::new();
            d.set("faction", a.faction as i64);
            d.set("province", a.province as i64);
            d.set("units", a.total_units() as i64);
            arr.push(&d.to_variant());
        }
        arr
    }

    /// Baked replay frames for the Nth battle of the last resolved turn. Returns
    /// { width, height, frames: [ { tick, fac:PackedByteArray, kind:PackedByteArray,
    ///   x:PackedFloat32Array, y:PackedFloat32Array, alive:PackedByteArray } ] }.
    #[func]
    fn get_last_battle_frames(&self, index: i64) -> Dict {
        let mut out = Dict::new();
        out.set("width", BATTLE_WIDTH);
        out.set("height", BATTLE_HEIGHT);
        let frames_arr = Array::<Variant>::new();
        out.set("frames", &frames_arr);
        let Some(battle) = self.battles.get(index.max(0) as usize) else {
            return out;
        };
        let mut frames_arr = Array::<Variant>::new();
        for frame in &battle.frames {
            let mut fd = Dict::new();
            fd.set("tick", frame.tick as i64);
            let mut fac = PackedByteArray::new();
            let mut kind = PackedByteArray::new();
            let mut xs = PackedFloat32Array::new();
            let mut ys = PackedFloat32Array::new();
            let mut zs = PackedFloat32Array::new();
            let mut alive = PackedByteArray::new();
            let mut facing = PackedByteArray::new();
            let mut state = PackedByteArray::new();
            let mut ax = PackedFloat32Array::new();
            let mut ay = PackedFloat32Array::new();
            for u in &frame.units {
                fac.push(u.faction as u8);
                kind.push(match u.kind {
                    UnitKind::Soldier => 0,
                    UnitKind::Bomber => 1,
                });
                xs.push(u.x);
                ys.push(u.y);
                zs.push(u.z);
                alive.push(if u.alive { 1 } else { 0 });
                facing.push(u.facing);
                state.push(u.state);
                ax.push(u.aim_x);
                ay.push(u.aim_y);
            }
            fd.set("fac", &fac);
            fd.set("kind", &kind);
            fd.set("x", &xs);
            fd.set("y", &ys);
            fd.set("z", &zs);
            fd.set("alive", &alive);
            fd.set("facing", &facing);
            fd.set("state", &state);
            fd.set("aim_x", &ax);
            fd.set("aim_y", &ay);
            frames_arr.push(&fd.to_variant());
        }
        out.set("frames", &frames_arr);
        out
    }

    /// Compact one-line-per-faction summary for a headless run (kept for smoke tests).
    #[func]
    fn run_campaign_summary(&self, seed: i64, turns: i64) -> GString {
        let (mut world, mut ledger) = scenario::procedural_world(seed as u64);
        let mut outcome = Outcome::Ongoing;
        let mut last = None;
        for _ in 0..turns.max(0) {
            let r = run_turn(&mut world, &mut ledger);
            outcome = r.outcome;
            last = Some(r);
            if !matches!(outcome, Outcome::Ongoing) {
                break;
            }
        }
        let mut text = format!(
            "turn={} txns={} trial_balance={:.4} outcome={:?}\n",
            world.turn,
            ledger.len(),
            ledger.trial_balance(),
            outcome
        );
        if let Some(r) = last {
            for fr in &r.factions {
                text.push_str(&format!(
                    "F{} dominion={:.1} land={} units={} thrones={} alive={}\n",
                    fr.faction, fr.total_dominion, fr.owned_land, fr.units_alive, fr.ascension, fr.alive
                ));
            }
        }
        GString::from(text.as_str())
    }
}

impl TwoWorldsEngine {
    fn store_custom_report(&mut self, report: BattleReport) -> Dict {
        let mut out = Dict::new();
        out.set("winner", report.winner.map(|x| x as i64).unwrap_or(-1));
        out.set("ticks", report.ticks as i64);
        out.set("frame_count", report.frames.len() as i64);
        let unit_count: i64 = report.initial.iter().map(|(_, n)| *n as i64).sum();
        out.set("unit_count", unit_count);
        self.battles = vec![report];
        out
    }
}
