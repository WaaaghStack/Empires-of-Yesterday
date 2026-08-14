//! Authoritative structure store for World Conquest (Phase 4).

use std::collections::HashMap;

use crate::world_edit::CorridorPathSpec;

pub const KIND_SPAWNER: u8 = 0;
pub const KIND_BARRACKS: u8 = 1;
pub const KIND_CORRIDOR_LINK: u8 = 2;
pub const KIND_HANGAR: u8 = 3;
pub const KIND_OTHER: u8 = 255;

pub const STATE_CONNECTING: u8 = 0;
pub const STATE_BUILDING: u8 = 1;
pub const STATE_ACTIVE: u8 = 2;
pub const STATE_OTHER: u8 = 255;

#[derive(Clone, Debug)]
pub struct StructureRecord {
    pub id: i32,
    pub team: u8,
    pub kind: u8,
    pub state: u8,
    pub gx: i32,
    pub gy: i32,
    pub path_keys: Vec<i32>,
    pub path_built: f32,
    pub path_len: i32,
    pub corridor_synced_built: i32,
    /// Outpost HP while BUILDING; < 0 when unused.
    pub health: f32,
    /// Seconds left in BUILDING phase; < 0 when not building.
    pub build_remaining: f32,
    pub spawn_timer: f32,
    /// Pump / Drain / Battery (SPAWNER_MODE_*). Ignored for non-spawners.
    pub spawner_mode: u8,
    /// Stored inject energy while Battery. Lost if the tile flips.
    pub battery_tank: f32,
    /// SCD1 domain version stamp (structures epoch at last write).
    pub version: u64,
}

#[derive(Clone, Debug)]
pub struct PersistedCorridor {
    pub slot: usize,
    pub team: u8,
    pub path_keys: Vec<i32>,
    pub corridor_synced_built: i32,
}

#[derive(Clone, Debug, Default)]
pub struct StructureStore {
    pub structures: HashMap<i32, StructureRecord>,
    pub persisted_corridors: Vec<PersistedCorridor>,
    pub ready: bool,
    /// SCD1 tombstones: removed structure id → domain version of the delete.
    /// Incremental pulls emit these so Godot can drop ghost markers without a full resync.
    pub tombstones: HashMap<i32, u64>,
}

pub fn kind_from_str(kind: &str) -> u8 {
    match kind {
        "spawner" => KIND_SPAWNER,
        "barracks" => KIND_BARRACKS,
        "corridor_link" => KIND_CORRIDOR_LINK,
        "hangar" => KIND_HANGAR,
        _ => KIND_OTHER,
    }
}

pub fn state_from_str(state: &str) -> u8 {
    match state {
        "connecting" => STATE_CONNECTING,
        "building" => STATE_BUILDING,
        "active" => STATE_ACTIVE,
        _ => STATE_OTHER,
    }
}

pub fn kind_to_str(kind: u8) -> &'static str {
    match kind {
        KIND_SPAWNER => "spawner",
        KIND_BARRACKS => "barracks",
        KIND_CORRIDOR_LINK => "corridor_link",
        KIND_HANGAR => "hangar",
        _ => "other",
    }
}

pub fn state_to_str(state: u8) -> &'static str {
    match state {
        STATE_CONNECTING => "connecting",
        STATE_BUILDING => "building",
        STATE_ACTIVE => "active",
        _ => "other",
    }
}

impl StructureStore {
    pub fn clear(&mut self) {
        self.structures.clear();
        self.persisted_corridors.clear();
        self.tombstones.clear();
        self.ready = false;
    }

    pub fn rebuild_from_records(
        &mut self,
        structures: Vec<StructureRecord>,
        corridors: Vec<PersistedCorridor>,
    ) {
        self.structures.clear();
        self.tombstones.clear();
        for st in structures {
            self.structures.insert(st.id, st);
        }
        self.persisted_corridors = corridors;
        self.ready = true;
    }

    pub fn upsert(&mut self, record: StructureRecord) {
        self.tombstones.remove(&record.id);
        self.structures.insert(record.id, record);
        self.ready = true;
    }

    /// Remove structure and record a tombstone at `version` (structures domain epoch).
    pub fn remove_with_tombstone(&mut self, sid: i32, version: u64) -> bool {
        if self.structures.remove(&sid).is_some() {
            self.tombstones.insert(sid, version);
            true
        } else {
            false
        }
    }

    pub fn remove(&mut self, sid: i32) {
        let _ = self.remove_with_tombstone(sid, 0);
    }

    /// Tombstone sids with version > last (for SCD1 incremental pull).
    pub fn tombstones_since(&self, last: u64) -> Vec<i32> {
        let mut ids: Vec<i32> = self
            .tombstones
            .iter()
            .filter(|(_, &v)| v > last)
            .map(|(&id, _)| id)
            .collect();
        ids.sort_unstable();
        ids
    }
}

/// SCD1 structures pull helper (used by `TerritorySim::pull_domain_since`).
/// Returns (living structure ids to emit, removed tombstone ids).
/// Full pulls omit tombstones (client replaces the whole cache).
pub fn scd1_structures_pull_ids(
    store: &StructureStore,
    last: u64,
    full: bool,
) -> (Vec<i32>, Vec<i32>) {
    let mut living: Vec<i32> = store
        .structures
        .iter()
        .filter(|(_, rec)| full || rec.version > last)
        .map(|(&id, _)| id)
        .collect();
    living.sort_unstable();
    let removed = if full {
        Vec::new()
    } else {
        store.tombstones_since(last)
    };
    (living, removed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remove_emits_tombstone_and_upsert_clears() {
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 7,
            team: 1,
            kind: KIND_SPAWNER,
            state: STATE_ACTIVE,
            gx: 1,
            gy: 0,
            path_keys: vec![],
            path_built: 0.0,
            path_len: 0,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
            spawner_mode: 0,
            battery_tank: 0.0,
            version: 1,
        });
        assert!(store.remove_with_tombstone(7, 5));
        assert!(!store.structures.contains_key(&7));
        assert_eq!(store.tombstones_since(4), vec![7]);
        assert!(store.tombstones_since(5).is_empty());
        store.upsert(StructureRecord {
            id: 7,
            team: 1,
            kind: KIND_SPAWNER,
            state: STATE_ACTIVE,
            gx: 1,
            gy: 0,
            path_keys: vec![],
            path_built: 0.0,
            path_len: 0,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
            spawner_mode: 0,
            battery_tank: 0.0,
            version: 6,
        });
        assert!(!store.tombstones.contains_key(&7));
    }

    #[test]
    fn remove_then_scd1_pull_emits_removed_ids() {
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 42,
            team: 1,
            kind: KIND_BARRACKS,
            state: STATE_ACTIVE,
            gx: 3,
            gy: 0,
            path_keys: vec![1, 2, 3],
            path_built: 3.0,
            path_len: 3,
            corridor_synced_built: 3,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
            spawner_mode: 0,
            battery_tank: 0.0,
            version: 2,
        });
        // Client last_version = 2 is caught up; remove stamps tombstone v=3.
        assert!(store.remove_with_tombstone(42, 3));
        let (living, removed) = scd1_structures_pull_ids(&store, 2, false);
        assert!(
            living.is_empty(),
            "deleted structure must not appear in living rows"
        );
        assert_eq!(
            removed,
            vec![42],
            "incremental pull must emit removed_ids for tombstone"
        );
        // Full seed: no tombstones (replace-all client cache).
        let (full_living, full_removed) = scd1_structures_pull_ids(&store, 2, true);
        assert!(full_living.is_empty());
        assert!(full_removed.is_empty());
        // Caught-up after applying v=3: no more removed.
        let (_, rem_caught) = scd1_structures_pull_ids(&store, 3, false);
        assert!(rem_caught.is_empty());
    }
}

impl StructureStore {
    pub fn patch_path_built(&mut self, sid: i32, path_built: f32) -> bool {
        let Some(st) = self.structures.get_mut(&sid) else {
            return false;
        };
        st.path_built = path_built;
        true
    }

    pub fn patch_state(&mut self, sid: i32, state: u8, path_built: Option<f32>) -> bool {
        let Some(st) = self.structures.get_mut(&sid) else {
            return false;
        };
        st.state = state;
        if let Some(pb) = path_built {
            st.path_built = pb;
        }
        true
    }

    pub fn enter_building_phase(
        &mut self,
        sid: i32,
        build_remaining: f32,
        max_health: f32,
    ) -> bool {
        let Some(st) = self.structures.get_mut(&sid) else {
            return false;
        };
        st.state = STATE_BUILDING;
        st.build_remaining = build_remaining;
        if has_build_phase(st.kind) {
            st.health = max_health;
        }
        true
    }

    pub fn patch_corridor_synced(&mut self, sid: i32, synced: i32) -> bool {
        if sid < 0 {
            let slot = (-(sid + 1)) as usize;
            let Some(corridor) = self.persisted_corridors.get_mut(slot) else {
                return false;
            };
            corridor.corridor_synced_built = synced;
            return true;
        }
        let Some(st) = self.structures.get_mut(&sid) else {
            return false;
        };
        st.corridor_synced_built = synced;
        true
    }

    pub fn connecting_count(&self, team: u8) -> i32 {
        self.structures
            .values()
            .filter(|st| st.team == team && st.state == STATE_CONNECTING)
            .count() as i32
    }

    fn built_cells(record: &StructureRecord) -> i32 {
        if record.path_keys.is_empty() {
            return 0;
        }
        if record.state == STATE_CONNECTING {
            return record.path_built.floor().max(1.0) as i32;
        }
        record.path_keys.len() as i32
    }

    fn qualifies_for_corridor_sync(record: &StructureRecord) -> bool {
        if !is_corridor_path_kind(record.kind) {
            return false;
        }
        match record.kind {
            KIND_SPAWNER | KIND_BARRACKS | KIND_HANGAR => {
                record.state == STATE_CONNECTING
                    || record.state == STATE_BUILDING
                    || record.state == STATE_ACTIVE
            }
            // ACTIVE allowed until Godot migrates the structure into bridge_corridors.
            KIND_CORRIDOR_LINK => {
                record.state == STATE_CONNECTING || record.state == STATE_ACTIVE
            }
            _ => false,
        }
    }

    pub fn corridor_specs(&self, sid_filter: &[i32], include_persisted: bool) -> Vec<CorridorPathSpec> {
        let mut out = Vec::new();
        let filter = !sid_filter.is_empty();
        let mut allowed: HashMap<i32, bool> = HashMap::new();
        if filter {
            for &sid in sid_filter {
                allowed.insert(sid, true);
            }
        }
        for st in self.structures.values() {
            if filter && !allowed.contains_key(&st.id) {
                continue;
            }
            if !Self::qualifies_for_corridor_sync(st) {
                continue;
            }
            out.push(CorridorPathSpec {
                sid: st.id,
                team: st.team,
                path_keys: st.path_keys.clone(),
                built_cells: Self::built_cells(st),
                synced_cells: st.corridor_synced_built.max(1),
            });
        }
        if filter || !include_persisted {
            return out;
        }
        for corridor in &self.persisted_corridors {
            let built = corridor.path_keys.len() as i32;
            out.push(CorridorPathSpec {
                sid: -((corridor.slot as i32) + 1),
                team: corridor.team,
                path_keys: corridor.path_keys.clone(),
                built_cells: built,
                synced_cells: corridor.corridor_synced_built.max(1),
            });
        }
        out
    }
}

pub fn is_corridor_path_kind(kind: u8) -> bool {
    kind == KIND_SPAWNER || kind == KIND_BARRACKS || kind == KIND_HANGAR || kind == KIND_CORRIDOR_LINK
}

pub fn has_build_phase(kind: u8) -> bool {
    kind == KIND_SPAWNER || kind == KIND_BARRACKS || kind == KIND_HANGAR
}
