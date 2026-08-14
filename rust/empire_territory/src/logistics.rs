//! Per-team logistics layer — **R1: roads and land bridges removed** (design lock R1).
//!
//! The road network no longer grows. `step_frame` builds no cells, credits no incremental
//! `path_built`, produces no cell-arrival ribbon events and never advances the road network
//! version, so the SCD1 Roads domain stays at epoch 0 and pulls come back empty.
//!
//! The module survives as a no-op shell (rather than being deleted) so the `DomainId::Roads`
//! slot, the Godot FFI entry points and the strain dictionary stay wired while the rest of R1
//! lands. Config fields are likewise kept so `configure_builders` / content tables keep
//! parsing; they are simply ignored.
//!
//! Structures left in `CONNECTING` are completed on the next step: with no road to wait for,
//! placement is instant-build (design lock F2 superseded by R1). Structures already ACTIVE are
//! untouched.

use crate::structures::{
    has_build_phase, is_corridor_path_kind, kind_to_str, StructureStore, KIND_BARRACKS,
    KIND_CORRIDOR_LINK, KIND_HANGAR, STATE_CONNECTING,
};

// --- Reconcile budget (B2). Retained for FFI/config compatibility; nothing reconciles now. ---
/// Default cells examined per team per frame during reconcile (unused under R1).
pub const LOGISTICS_RECONCILE_CELLS_PER_FRAME_DEFAULT: usize = 512;
/// Hard cap even if Godot config requests more.
pub const LOGISTICS_RECONCILE_CELLS_PER_FRAME_HARD_CAP: usize = 2048;

#[derive(Clone, Debug)]
pub struct LogisticsConfig {
    pub road_cells_per_sec: f32,
    pub outpost_build_sec: f32,
    pub barracks_build_sec: f32,
    pub hangar_build_sec: f32,
    pub outpost_max_health: f32,
    pub reconcile_cells_per_frame: usize,
    pub full_recal_interval_sec: f32,
    pub placement_heat_decay_per_sec: f32,
    pub burst_base: f32,
    pub burst_ratio: f32,
    pub structure_drain_spawner: f32,
    pub structure_drain_barracks: f32,
    pub structure_drain_hangar: f32,
    pub structure_drain_corridor: f32,
    pub strain_sensitivity: f32,
}

impl Default for LogisticsConfig {
    fn default() -> Self {
        Self {
            road_cells_per_sec: 1.0,
            outpost_build_sec: 5.0,
            barracks_build_sec: 5.0,
            hangar_build_sec: 5.0,
            outpost_max_health: 10.0,
            reconcile_cells_per_frame: LOGISTICS_RECONCILE_CELLS_PER_FRAME_DEFAULT,
            full_recal_interval_sec: 25.0,
            placement_heat_decay_per_sec: 0.85,
            burst_base: 0.02,
            burst_ratio: 1.35,
            structure_drain_spawner: 0.04,
            structure_drain_barracks: 0.06,
            structure_drain_hangar: 0.06,
            structure_drain_corridor: 0.03,
            strain_sensitivity: 1.0,
        }
    }
}

/// Clamp Godot-provided reconcile budget to hard cap (B2).
pub fn clamp_reconcile_budget(requested: usize) -> usize {
    requested
        .max(1)
        .min(LOGISTICS_RECONCILE_CELLS_PER_FRAME_HARD_CAP)
}

#[derive(Clone, Debug)]
pub struct CellArrivalEvent {
    pub sid: i32,
    pub seg_from_idx: i32,
    pub kind: u8,
}

#[derive(Clone, Debug)]
pub struct PathCompletionEvent {
    pub sid: i32,
    pub gx: i32,
    pub gy: i32,
    pub team: u8,
    pub is_corridor_link: bool,
    pub kind: u8,
}

#[derive(Clone, Debug, Default)]
pub struct LogisticsStepEvents {
    pub visual_dirty: bool,
    /// Always empty under R1 — no road cells are laid, so there is no ribbon to animate.
    pub cell_arrivals: Vec<CellArrivalEvent>,
    pub path_completions: Vec<PathCompletionEvent>,
    pub completed_corridor_sids: Vec<i32>,
    /// Always empty under R1.
    pub new_built_cells: Vec<i32>,
    pub friendly_output_mult: f32,
    pub hostile_output_mult: f32,
    /// Frozen at 0 under R1 — road caches never need invalidating.
    pub road_network_version: u32,
    pub reconcile_cells_examined: u32,
}

#[derive(Clone, Debug, Default)]
pub struct LogisticsLayer {
    configured: bool,
    pub player_home: (i32, i32),
    pub enemy_home: (i32, i32),
    /// Never bumped under R1.
    pub road_network_version: u32,
}

impl LogisticsLayer {
    pub fn is_configured(&self) -> bool {
        self.configured
    }

    pub fn configure(
        &mut self,
        _tile_count: usize,
        _grid_w: i32,
        _grid_h: i32,
        _graph_topology: bool,
        _neighbors: Vec<[i32; 6]>,
        _neighbor_count: Vec<u8>,
        _cfg: &LogisticsConfig,
    ) {
        self.configured = true;
    }

    /// R1: nothing to route. Placement no longer reserves or grows road cells.
    pub fn register_terminal(
        &mut self,
        _sid: i32,
        _store: &mut StructureStore,
        _team: u8,
        _grid_w: i32,
        _cfg: &LogisticsConfig,
    ) {
    }

    pub fn unregister_terminal(&mut self, _sid: i32, _store: &StructureStore, _team: u8) {}

    pub fn seed_from_store(&mut self, _store: &StructureStore, _cfg: &LogisticsConfig) {}

    /// Empty under R1 — no road network exists, so the Roads domain pull is always empty.
    pub fn built_mask(&self, _team: u8) -> Vec<u8> {
        Vec::new()
    }

    pub fn planned_mask(&self, _team: u8) -> Vec<u8> {
        Vec::new()
    }

    pub fn route_mask(&self, _team: u8) -> Vec<u8> {
        Vec::new()
    }

    /// Complete any leftover CONNECTING structures; grow nothing. Output multipliers are
    /// pinned at 1.0 because logistics strain is gone with the roads.
    pub fn step_frame(
        &mut self,
        dt: f32,
        store: &mut StructureStore,
        _grid_w: i32,
        _grid_h: i32,
        cfg: &LogisticsConfig,
    ) -> LogisticsStepEvents {
        let mut result = LogisticsStepEvents {
            friendly_output_mult: 1.0,
            hostile_output_mult: 1.0,
            road_network_version: self.road_network_version,
            ..Default::default()
        };
        if dt <= 0.0 {
            return result;
        }

        let mut pending: Vec<i32> = store
            .structures
            .values()
            .filter(|st| st.state == STATE_CONNECTING && is_corridor_path_kind(st.kind))
            .map(|st| st.id)
            .collect();
        pending.sort_unstable();

        for sid in pending {
            let Some(done) = complete_without_road(store, sid, cfg) else {
                continue;
            };
            if done.is_corridor_link {
                result.completed_corridor_sids.push(done.sid);
            }
            result.path_completions.push(done);
            result.visual_dirty = true;
        }
        result
    }
}

fn build_sec_for_kind(kind: u8, cfg: &LogisticsConfig) -> f32 {
    if kind == KIND_BARRACKS {
        cfg.barracks_build_sec
    } else if kind == KIND_HANGAR {
        cfg.hangar_build_sec
    } else {
        cfg.outpost_build_sec
    }
}

/// R1 instant connect: treat the structure as if it were already road-linked and hand it
/// straight to its build phase (or ACTIVE for kinds that have none).
fn complete_without_road(
    store: &mut StructureStore,
    sid: i32,
    cfg: &LogisticsConfig,
) -> Option<PathCompletionEvent> {
    let st = store.structures.get_mut(&sid)?;
    let path_len = if st.path_keys.is_empty() {
        st.path_len
    } else {
        st.path_keys.len() as i32
    };
    st.path_len = path_len;
    st.path_built = path_len as f32;
    let kind = st.kind;
    let is_corridor_link = kind == KIND_CORRIDOR_LINK;
    if is_corridor_link {
        st.state = crate::structures::STATE_ACTIVE;
        st.build_remaining = 0.0;
    } else {
        st.state = crate::structures::STATE_BUILDING;
        st.build_remaining = build_sec_for_kind(kind, cfg);
        if has_build_phase(kind) {
            st.health = cfg.outpost_max_health;
        }
    }
    Some(PathCompletionEvent {
        sid,
        gx: st.gx,
        gy: st.gy,
        team: st.team,
        is_corridor_link,
        kind,
    })
}

pub fn kind_str(kind: u8) -> &'static str {
    kind_to_str(kind)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::OWNER_FRIENDLY;
    use crate::structures::{StructureRecord, KIND_SPAWNER, STATE_BUILDING};

    fn connecting_spawner(id: i32, path_keys: Vec<i32>) -> StructureRecord {
        let path_len = path_keys.len() as i32;
        StructureRecord {
            id,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 3,
            gy: 0,
            path_keys,
            path_built: 1.0,
            path_len,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
            spawner_mode: 0,
            battery_tank: 0.0,
            version: 0,
        }
    }

    #[test]
    fn no_roads_are_built() {
        let mut layer = LogisticsLayer::default();
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        store.upsert(connecting_spawner(1, vec![0, 1, 2, 3]));
        layer.configure(256, 16, 16, false, Vec::new(), Vec::new(), &cfg);
        layer.register_terminal(1, &mut store, OWNER_FRIENDLY, 16, &cfg);
        for _ in 0..8 {
            let frame = layer.step_frame(1.0, &mut store, 16, 16, &cfg);
            assert!(frame.new_built_cells.is_empty(), "R1 lays no road cells");
            assert!(frame.cell_arrivals.is_empty(), "R1 emits no ribbon arrivals");
            assert_eq!(frame.road_network_version, 0, "roads domain stays at epoch 0");
        }
        assert!(layer.built_mask(OWNER_FRIENDLY).is_empty());
        assert!(layer.planned_mask(OWNER_FRIENDLY).is_empty());
        assert!(layer.route_mask(OWNER_FRIENDLY).is_empty());
    }

    #[test]
    fn connecting_structure_builds_immediately() {
        let mut layer = LogisticsLayer::default();
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        store.upsert(connecting_spawner(1, vec![0, 1, 2, 3]));
        layer.configure(256, 16, 16, false, Vec::new(), Vec::new(), &cfg);
        let frame = layer.step_frame(0.016, &mut store, 16, 16, &cfg);
        assert_eq!(frame.path_completions.len(), 1);
        let st = store.structures.get(&1).unwrap();
        assert_eq!(st.state, STATE_BUILDING, "no road gate before building");
        assert_eq!(st.path_built, 4.0);
    }

    #[test]
    fn output_mult_is_always_one() {
        let mut layer = LogisticsLayer::default();
        let cfg = LogisticsConfig::default();
        let mut store = StructureStore::default();
        store.upsert(connecting_spawner(1, vec![0, 1, 2, 3]));
        store.upsert(connecting_spawner(2, vec![0, 16, 17, 18]));
        layer.configure(256, 16, 16, false, Vec::new(), Vec::new(), &cfg);
        let frame = layer.step_frame(0.5, &mut store, 16, 16, &cfg);
        assert_eq!(frame.friendly_output_mult, 1.0);
        assert_eq!(frame.hostile_output_mult, 1.0);
    }

    #[test]
    fn reconcile_budget_is_hard_capped() {
        assert_eq!(
            clamp_reconcile_budget(LOGISTICS_RECONCILE_CELLS_PER_FRAME_HARD_CAP * 10),
            LOGISTICS_RECONCILE_CELLS_PER_FRAME_HARD_CAP
        );
        assert_eq!(clamp_reconcile_budget(0), 1);
    }
}
