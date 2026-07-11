//! World Conquest session tick — building timers, construction damage, barracks/hangar spawns (Phase 7).

use crate::agents::AgentLayer;
use crate::bombers::BomberLayer;
use crate::economy::{ContentTables, RESOURCE_SLOTS, UNIT_SOLDIER};
use crate::resources::ResourceWallet;
use crate::sim::{TerritoryKernel, OWNER_FRIENDLY, OWNER_HOSTILE, MIN_CLAIM_PRESSURE};
use crate::structures::{
    has_build_phase, StructureStore, KIND_BARRACKS, KIND_HANGAR, KIND_SPAWNER, STATE_ACTIVE,
    STATE_BUILDING,
};

const CLAIM_DOMINANCE_RATIO: f32 = 1.15;

#[derive(Clone, Debug)]
pub struct WorldSessionConfig {
    pub outpost_build_sec: f32,
    pub barracks_build_sec: f32,
    pub outpost_max_health: f32,
    pub outpost_enemy_dps: f32,
    pub barracks_spawn_interval: f32,
    pub barracks_max_active: u32,
    pub global_soldier_cap: u32,
    pub soldier_spawn_cost: f32,
    pub hangar_build_sec: f32,
    pub hangar_spawn_interval: f32,
    pub hangar_max_active: u32,
    pub global_bomber_cap: u32,
    pub bomber_spawn_cost: f32,
    pub soldier_upkeep_per_sec: f32,
    pub upkeep_deficit_dps: f32,
}

impl Default for WorldSessionConfig {
    fn default() -> Self {
        Self {
            outpost_build_sec: 5.0,
            barracks_build_sec: 60.0,
            outpost_max_health: 10.0,
            outpost_enemy_dps: 3.0,
            barracks_spawn_interval: 10.0,
            barracks_max_active: 5,
            global_soldier_cap: 100,
            soldier_spawn_cost: 3.0,
            hangar_build_sec: 60.0,
            hangar_spawn_interval: 10.0,
            hangar_max_active: 5,
            global_bomber_cap: 100,
            bomber_spawn_cost: 3.0,
            soldier_upkeep_per_sec: 0.15,
            upkeep_deficit_dps: 2.5,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct WorldSessionEvents {
    pub activated_sids: Vec<i32>,
    pub activated_spawner_sids: Vec<i32>,
    pub destroyed_sids: Vec<i32>,
    pub spawned_barracks_sids: Vec<i32>,
    pub spawned_hangar_sids: Vec<i32>,
    pub friendly_aurelium_spent: f32,
    pub friendly_deficit_dps: f32,
    pub hostile_deficit_dps: f32,
    pub needs_sim_sync: bool,
    pub marker_dirty: bool,
}

fn build_sec_for_kind(kind: u8, cfg: &WorldSessionConfig) -> f32 {
    if kind == KIND_BARRACKS {
        cfg.barracks_build_sec
    } else if kind == KIND_HANGAR {
        cfg.hangar_build_sec
    } else {
        cfg.outpost_build_sec
    }
}

fn takes_territory_damage(kind: u8, state: u8) -> bool {
    has_build_phase(kind) && (state == STATE_BUILDING || state == STATE_ACTIVE)
}

fn construction_dps_at(
    kernel: &TerritoryKernel,
    gx: i32,
    gy: i32,
    team: u8,
    cfg: &WorldSessionConfig,
) -> f32 {
    let idx = kernel.cell_index(gx, gy);
    if idx < 0 {
        return 0.0;
    }
    let ui = idx as usize;
    let owner = kernel.owner_at_index(ui);
    let (own_p, opp_p) = if team == OWNER_FRIENDLY {
        (kernel.pressure_friendly[ui], kernel.pressure_hostile[ui])
    } else {
        (kernel.pressure_hostile[ui], kernel.pressure_friendly[ui])
    };
    let mut ratio = CLAIM_DOMINANCE_RATIO;
    ratio *= kernel.claim_ratio_mult_at(ui);
    if opp_p >= MIN_CLAIM_PRESSURE && opp_p > own_p * ratio {
        return cfg.outpost_enemy_dps;
    }
    if owner == team {
        return 0.0;
    }
    if owner == OWNER_FRIENDLY || owner == OWNER_HOSTILE {
        return cfg.outpost_enemy_dps;
    }
    0.0
}

fn apply_soldier_upkeep(
    living: u32,
    balance: &mut [f32; RESOURCE_SLOTS],
    upkeep_rates: &[f32; RESOURCE_SLOTS],
    deficit_dps: f32,
    dt: f32,
) -> f32 {
    if living == 0 || dt <= 0.0 {
        return 0.0;
    }
    let count = living as f32;
    let au_upkeep = count * upkeep_rates[0] * dt;
    let au_paid = au_upkeep.min(balance[0]);
    balance[0] -= au_paid;
    for i in 1..RESOURCE_SLOTS {
        if upkeep_rates[i] > 0.0 {
            let need = count * upkeep_rates[i] * dt;
            let paid = need.min(balance[i]);
            balance[i] -= paid;
        }
    }
    let deficit = au_upkeep - au_paid;
    if deficit > 0.0 && au_upkeep > 0.0 {
        deficit_dps * (deficit / au_upkeep)
    } else {
        0.0
    }
}

fn apply_soldier_upkeep_legacy(
    living: u32,
    balance: &mut f32,
    upkeep_per_sec: f32,
    deficit_dps: f32,
    dt: f32,
) -> f32 {
    if living == 0 || dt <= 0.0 {
        return 0.0;
    }
    let upkeep = living as f32 * upkeep_per_sec * dt;
    let paid = upkeep.min(*balance);
    *balance -= paid;
    let deficit = upkeep - paid;
    if deficit > 0.0 && upkeep > 0.0 {
        deficit_dps * (deficit / upkeep)
    } else {
        0.0
    }
}

fn can_afford_spawn_legacy(team: u8, legacy_aurelium: f32, legacy_cost: f32) -> bool {
    team != OWNER_FRIENDLY || legacy_aurelium >= legacy_cost
}

pub fn tick_world_session(
    kernel: &TerritoryKernel,
    store: &mut StructureStore,
    agents: Option<&mut AgentLayer>,
    bombers: Option<&mut BomberLayer>,
    dt: f32,
    mut wallet: Option<&mut ResourceWallet>,
    mut legacy_friendly_aurelium: Option<&mut f32>,
    tables: &ContentTables,
    cfg: &WorldSessionConfig,
) -> WorldSessionEvents {
    let mut events = WorldSessionEvents::default();
    if dt <= 0.0 || !store.ready {
        return events;
    }

    let soldier_upkeep = tables.unit_upkeep_resources[UNIT_SOLDIER];
    let soldier_spawn_cost = tables.structure_spawn_resources[KIND_BARRACKS as usize];
    let bomber_spawn_cost = tables.structure_spawn_resources[KIND_HANGAR as usize];

    if let Some(agents) = agents.as_ref() {
        let friendly_living = agents.living_count_for_team(OWNER_FRIENDLY);
        let hostile_living = agents.living_count_for_team(OWNER_HOSTILE);
        if let Some(w) = wallet.as_deref_mut() {
            events.friendly_deficit_dps = apply_soldier_upkeep(
                friendly_living,
                &mut w.friendly,
                &soldier_upkeep,
                cfg.upkeep_deficit_dps,
                dt,
            );
            events.hostile_deficit_dps = apply_soldier_upkeep(
                hostile_living,
                &mut w.hostile,
                &soldier_upkeep,
                cfg.upkeep_deficit_dps,
                dt,
            );
        } else if let Some(legacy_au) = legacy_friendly_aurelium.as_deref_mut() {
            events.friendly_deficit_dps = apply_soldier_upkeep_legacy(
                friendly_living,
                legacy_au,
                cfg.soldier_upkeep_per_sec,
                cfg.upkeep_deficit_dps,
                dt,
            );
        }
    }

    let ids: Vec<i32> = store.structures.keys().copied().collect();
    for sid in ids {
        let Some(st) = store.structures.get(&sid).cloned() else {
            continue;
        };
        if !takes_territory_damage(st.kind, st.state) {
            continue;
        }
        let dps = construction_dps_at(kernel, st.gx, st.gy, st.team, cfg);
        if dps <= 0.0 {
            continue;
        }
        let Some(rec) = store.structures.get_mut(&sid) else {
            continue;
        };
        if rec.health < 0.0 {
            rec.health = cfg.outpost_max_health;
        }
        rec.health -= dps * dt;
        if rec.health <= 0.0 {
            events.destroyed_sids.push(sid);
            events.marker_dirty = true;
        }
    }
    for sid in &events.destroyed_sids.clone() {
        store.remove(*sid);
    }

    let ids: Vec<i32> = store.structures.keys().copied().collect();
    for sid in ids {
        let Some(st) = store.structures.get_mut(&sid) else {
            continue;
        };
        if !has_build_phase(st.kind) || st.state != STATE_BUILDING {
            continue;
        }
        let build_sec = build_sec_for_kind(st.kind, cfg);
        if st.build_remaining < 0.0 {
            st.build_remaining = build_sec;
        }
        st.build_remaining -= dt;
        if st.build_remaining > 0.0 {
            continue;
        }
        st.state = STATE_ACTIVE;
        st.build_remaining = -1.0;
        if st.health < 0.0 {
            st.health = cfg.outpost_max_health;
        }
        st.spawn_timer = 0.0;
        events.activated_sids.push(sid);
        events.marker_dirty = true;
        if st.kind == KIND_SPAWNER {
            events.activated_spawner_sids.push(sid);
        }
        events.needs_sim_sync = true;
    }

    if let Some(agents) = agents {
        let ids: Vec<i32> = store.structures.keys().copied().collect();
        for sid in ids {
            let Some(st) = store.structures.get(&sid) else {
                continue;
            };
            if st.kind != KIND_BARRACKS || st.state != STATE_ACTIVE {
                continue;
            }
            let team = st.team;
            let gx = st.gx;
            let gy = st.gy;
            let mut spawn_timer = st.spawn_timer + dt;
            if spawn_timer < cfg.barracks_spawn_interval {
                if let Some(rec) = store.structures.get_mut(&sid) {
                    rec.spawn_timer = spawn_timer;
                }
                continue;
            }
            if agents.living_for_barracks(sid) >= cfg.barracks_max_active {
                if let Some(rec) = store.structures.get_mut(&sid) {
                    rec.spawn_timer = spawn_timer;
                }
                continue;
            }
            if agents.living_count() >= cfg.global_soldier_cap {
                if let Some(rec) = store.structures.get_mut(&sid) {
                    rec.spawn_timer = spawn_timer;
                }
                continue;
            }
            let legacy_au = legacy_friendly_aurelium
                .as_deref()
                .copied()
                .unwrap_or(0.0);
            let can_spawn = if let Some(w) = wallet.as_deref() {
                let bal = if team == OWNER_FRIENDLY {
                    &w.friendly
                } else {
                    &w.hostile
                };
                ContentTables::can_afford_resources(bal, &soldier_spawn_cost)
            } else {
                can_afford_spawn_legacy(team, legacy_au, cfg.soldier_spawn_cost)
            };
            if !can_spawn {
                if let Some(rec) = store.structures.get_mut(&sid) {
                    rec.spawn_timer = spawn_timer;
                }
                continue;
            }
            if agents.try_spawn(kernel, sid, team, gx, gy) {
                if let Some(w) = wallet.as_deref_mut() {
                    let bal = if team == OWNER_FRIENDLY {
                        &mut w.friendly
                    } else {
                        &mut w.hostile
                    };
                    ContentTables::apply_resource_cost(bal, &soldier_spawn_cost);
                    if team == OWNER_FRIENDLY {
                        events.friendly_aurelium_spent += soldier_spawn_cost[0];
                    }
                } else if team == OWNER_FRIENDLY {
                    if let Some(legacy_au) = legacy_friendly_aurelium.as_deref_mut() {
                        *legacy_au -= cfg.soldier_spawn_cost;
                    }
                    events.friendly_aurelium_spent += cfg.soldier_spawn_cost;
                }
                spawn_timer -= cfg.barracks_spawn_interval;
                events.spawned_barracks_sids.push(sid);
                events.marker_dirty = true;
            }
            if let Some(rec) = store.structures.get_mut(&sid) {
                rec.spawn_timer = spawn_timer;
            }
        }
    }

    if let Some(bombers) = bombers {
    let ids: Vec<i32> = store.structures.keys().copied().collect();
    for sid in ids {
        let Some(st) = store.structures.get(&sid) else {
            continue;
        };
        if st.kind != KIND_HANGAR || st.state != STATE_ACTIVE {
            continue;
        }
        let team = st.team;
        let gx = st.gx;
        let gy = st.gy;
        let mut spawn_timer = st.spawn_timer + dt;
        if spawn_timer < cfg.hangar_spawn_interval {
            if let Some(rec) = store.structures.get_mut(&sid) {
                rec.spawn_timer = spawn_timer;
            }
            continue;
        }
        if bombers.living_for_hangar(sid) >= cfg.hangar_max_active {
            if let Some(rec) = store.structures.get_mut(&sid) {
                rec.spawn_timer = spawn_timer;
            }
            continue;
        }
        if bombers.living_count() >= cfg.global_bomber_cap {
            if let Some(rec) = store.structures.get_mut(&sid) {
                rec.spawn_timer = spawn_timer;
            }
            continue;
        }
        let legacy_au = legacy_friendly_aurelium
            .as_deref()
            .copied()
            .unwrap_or(0.0);
        let can_spawn = if let Some(w) = wallet.as_deref() {
            let bal = if team == OWNER_FRIENDLY {
                &w.friendly
            } else {
                &w.hostile
            };
            ContentTables::can_afford_resources(bal, &bomber_spawn_cost)
        } else {
            can_afford_spawn_legacy(team, legacy_au, cfg.bomber_spawn_cost)
        };
        if !can_spawn {
            if let Some(rec) = store.structures.get_mut(&sid) {
                rec.spawn_timer = spawn_timer;
            }
            continue;
        }
        if bombers.try_spawn(kernel, sid, team, gx, gy) {
            if let Some(w) = wallet.as_deref_mut() {
                let bal = if team == OWNER_FRIENDLY {
                    &mut w.friendly
                } else {
                    &mut w.hostile
                };
                ContentTables::apply_resource_cost(bal, &bomber_spawn_cost);
                if team == OWNER_FRIENDLY {
                    events.friendly_aurelium_spent += bomber_spawn_cost[0];
                }
            } else if team == OWNER_FRIENDLY {
                if let Some(legacy_au) = legacy_friendly_aurelium.as_deref_mut() {
                    *legacy_au -= cfg.bomber_spawn_cost;
                }
                events.friendly_aurelium_spent += cfg.bomber_spawn_cost;
            }
            spawn_timer -= cfg.hangar_spawn_interval;
            events.spawned_hangar_sids.push(sid);
            events.marker_dirty = true;
        }
        if let Some(rec) = store.structures.get_mut(&sid) {
            rec.spawn_timer = spawn_timer;
        }
    }
    }

    events
}
