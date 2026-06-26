//! World Conquest session tick — building timers, construction damage, barracks spawns (Phase 7).

use crate::agents::AgentLayer;
use crate::sim::{TerritoryKernel, OWNER_FRIENDLY, OWNER_HOSTILE, MIN_CLAIM_PRESSURE};
use crate::structures::{
    has_build_phase, StructureStore, KIND_BARRACKS, KIND_SPAWNER, STATE_ACTIVE, STATE_BUILDING,
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
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct WorldSessionEvents {
    pub activated_sids: Vec<i32>,
    pub activated_spawner_sids: Vec<i32>,
    pub pending_claim_gx: Vec<i32>,
    pub pending_claim_gy: Vec<i32>,
    pub destroyed_sids: Vec<i32>,
    pub spawned_barracks_sids: Vec<i32>,
    pub friendly_aurelium_spent: f32,
    pub needs_sim_sync: bool,
    pub marker_dirty: bool,
}

fn build_sec_for_kind(kind: u8, cfg: &WorldSessionConfig) -> f32 {
    if kind == KIND_BARRACKS {
        cfg.barracks_build_sec
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
    if owner == team {
        return 0.0;
    }
    if owner == OWNER_FRIENDLY || owner == OWNER_HOSTILE {
        return cfg.outpost_enemy_dps;
    }
    let (own_p, opp_p) = if team == OWNER_FRIENDLY {
        (kernel.pressure_friendly[ui], kernel.pressure_hostile[ui])
    } else {
        (kernel.pressure_hostile[ui], kernel.pressure_friendly[ui])
    };
    let mut ratio = CLAIM_DOMINANCE_RATIO;
    ratio *= kernel.claim_ratio_mult_at(ui);
    if opp_p >= MIN_CLAIM_PRESSURE && opp_p > own_p * ratio {
        cfg.outpost_enemy_dps
    } else {
        0.0
    }
}

pub fn tick_world_session(
    kernel: &TerritoryKernel,
    store: &mut StructureStore,
    agents: Option<&mut AgentLayer>,
    dt: f32,
    friendly_aurelium: &mut f32,
    cfg: &WorldSessionConfig,
) -> WorldSessionEvents {
    let mut events = WorldSessionEvents::default();
    if dt <= 0.0 || !store.ready {
        return events;
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
            let idx = kernel.cell_index(st.gx, st.gy);
            if idx >= 0 {
                let ui = idx as usize;
                if kernel.owner_at_index(ui) != st.team {
                    events.pending_claim_gx.push(st.gx);
                    events.pending_claim_gy.push(st.gy);
                    events.needs_sim_sync = true;
                }
            }
        } else {
            events.needs_sim_sync = true;
        }
    }

    let Some(agents) = agents else {
        return events;
    };
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
        if *friendly_aurelium < cfg.soldier_spawn_cost {
            if let Some(rec) = store.structures.get_mut(&sid) {
                rec.spawn_timer = spawn_timer;
            }
            continue;
        }
        if agents.try_spawn(kernel, sid, team, gx, gy) {
            *friendly_aurelium -= cfg.soldier_spawn_cost;
            events.friendly_aurelium_spent += cfg.soldier_spawn_cost;
            spawn_timer -= cfg.barracks_spawn_interval;
            events.spawned_barracks_sids.push(sid);
            events.marker_dirty = true;
        }
        if let Some(rec) = store.structures.get_mut(&sid) {
            rec.spawn_timer = spawn_timer;
        }
    }

    events
}
