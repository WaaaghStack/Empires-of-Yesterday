//! Presentation transaction log.
//!
//! **Architecture (authoritative model):**
//! - **Main tables** live only in Rust (owners, structures, logistics built cells, agents).
//! - **Transaction log** records what *changed* since the last visual pull.
//! - Godot does **not** re-scan main tables every frame; it drains this log and applies
//!   deltas to the render cache (markers, MultiMesh roads, ownership texture).
//!
//! Think: database primary tables + write-ahead / change feed for the UI.

use godot::builtin::{PackedByteArray, PackedFloat32Array, PackedInt32Array};
use godot::prelude::*;

use crate::logistics::LogisticsStepEvents;
use crate::structures::StructureStore;

type GdDictionary = Dictionary<Variant, Variant>;

#[derive(Clone, Debug, Default)]
pub struct PresentationTxn {
    /// Owner cells that changed (sim truth).
    pub owner_indices: Vec<i32>,
    pub owner_values: Vec<u8>,
    /// Pre-mapped R8 display bytes for the ownership overlay.
    pub display_indices: Vec<i32>,
    pub display_r8: Vec<u8>,
    pub friendly_tiles: i32,
    pub hostile_tiles: i32,

    /// Structure field patches (not full table dumps).
    pub path_built_sids: Vec<i32>,
    pub path_built_vals: Vec<f32>,
    pub state_sids: Vec<i32>,
    /// Packed as structure state u8 (see structures::STATE_*).
    pub state_vals: Vec<u8>,

    /// New logistics network road cells (cell keys).
    pub new_road_cells: Vec<i32>,
    /// Structure ids that completed path / need marker refresh.
    pub completed_sids: Vec<i32>,
    pub marker_dirty_sids: Vec<i32>,

    /// True if any structure field in the main table changed this frame.
    pub structures_dirty: bool,
}

impl PresentationTxn {
    pub fn clear(&mut self) {
        self.owner_indices.clear();
        self.owner_values.clear();
        self.display_indices.clear();
        self.display_r8.clear();
        self.friendly_tiles = 0;
        self.hostile_tiles = 0;
        self.path_built_sids.clear();
        self.path_built_vals.clear();
        self.state_sids.clear();
        self.state_vals.clear();
        self.new_road_cells.clear();
        self.completed_sids.clear();
        self.marker_dirty_sids.clear();
        self.structures_dirty = false;
    }

    pub fn is_empty(&self) -> bool {
        self.owner_indices.is_empty()
            && self.display_indices.is_empty()
            && self.path_built_sids.is_empty()
            && self.state_sids.is_empty()
            && self.new_road_cells.is_empty()
            && self.completed_sids.is_empty()
            && self.marker_dirty_sids.is_empty()
            && !self.structures_dirty
    }

    pub fn push_owner_delta(
        &mut self,
        owner_idx: Vec<i32>,
        owner_val: Vec<u8>,
        display_idx: Vec<i32>,
        display_r8: Vec<u8>,
        friendly_tiles: i32,
        hostile_tiles: i32,
    ) {
        self.owner_indices.extend(owner_idx);
        self.owner_values.extend(owner_val);
        self.display_indices.extend(display_idx);
        self.display_r8.extend(display_r8);
        self.friendly_tiles = friendly_tiles;
        self.hostile_tiles = hostile_tiles;
    }

    pub fn push_path_built(&mut self, sid: i32, path_built: f32) {
        self.path_built_sids.push(sid);
        self.path_built_vals.push(path_built);
        self.structures_dirty = true;
    }

    pub fn push_state(&mut self, sid: i32, state: u8) {
        self.state_sids.push(sid);
        self.state_vals.push(state);
        self.structures_dirty = true;
        self.marker_dirty_sids.push(sid);
    }

    pub fn merge_logistics(&mut self, events: &LogisticsStepEvents) {
        if !events.new_built_cells.is_empty() {
            self.new_road_cells
                .extend(events.new_built_cells.iter().copied());
        }
        for ev in &events.cell_arrivals {
            // path_built advances with each segment; main table already patched by logistics.
            // Emit txn so Godot can update render cache without a full structure snapshot.
            // path_built value is filled by caller after reading the structure store.
            let _ = ev;
        }
        for ev in &events.path_completions {
            self.completed_sids.push(ev.sid);
            self.marker_dirty_sids.push(ev.sid);
            self.structures_dirty = true;
        }
        for &sid in &events.completed_corridor_sids {
            self.completed_sids.push(sid);
            self.marker_dirty_sids.push(sid);
            self.structures_dirty = true;
        }
        if events.visual_dirty {
            self.structures_dirty = true;
        }
    }

    /// After logistics step, fill path_built patches from the authoritative store.
    pub fn fill_path_built_from_arrivals(
        &mut self,
        store: &StructureStore,
        events: &LogisticsStepEvents,
    ) {
        for ev in &events.cell_arrivals {
            if let Some(st) = store.structures.get(&ev.sid) {
                self.push_path_built(ev.sid, st.path_built);
            }
        }
        for ev in &events.path_completions {
            if let Some(st) = store.structures.get(&ev.sid) {
                self.push_path_built(ev.sid, st.path_built);
                self.push_state(ev.sid, st.state);
            }
        }
    }

    pub fn take(&mut self) -> PresentationTxn {
        let out = self.clone();
        self.clear();
        out
    }

    pub fn to_dict(&self) -> GdDictionary {
        let mut out = GdDictionary::new();
        // Owner / overlay deltas (same shape as legacy consume_owner_overlay_delta).
        let mut owners = GdDictionary::new();
        owners.set("indices", &vec_to_packed_i32(&self.display_indices));
        owners.set("values", &vec_to_packed_byte(&self.display_r8));
        owners.set("owner_indices", &vec_to_packed_i32(&self.owner_indices));
        owners.set("owner_values", &vec_to_packed_byte(&self.owner_values));
        out.set("owners", &owners);
        out.set("friendly_tiles", self.friendly_tiles);
        out.set("hostile_tiles", self.hostile_tiles);

        // Structure field transactions (apply to render cache; do not re-fetch full table).
        out.set("path_built_sids", &vec_to_packed_i32(&self.path_built_sids));
        out.set("path_built_vals", &vec_to_packed_f32(&self.path_built_vals));
        out.set("state_sids", &vec_to_packed_i32(&self.state_sids));
        out.set("state_vals", &vec_to_packed_byte(&self.state_vals));
        // Human-readable state strings for GDScript cache (parallel to state_vals).
        let mut state_names = PackedByteArray::new();
        // Not used as packed strings — expose as packed ints only; GD maps STATE_* codes.

        out.set("new_road_cells", &vec_to_packed_i32(&self.new_road_cells));
        out.set("completed_sids", &vec_to_packed_i32(&self.completed_sids));
        out.set(
            "marker_dirty_sids",
            &vec_to_packed_i32(&self.marker_dirty_sids),
        );
        out.set("structures_dirty", self.structures_dirty);
        // Empty full snapshot by default — only when caller explicitly requests one.
        out.set("structures", &GdDictionary::new());
        let _ = state_names;
        out
    }
}

fn vec_to_packed_i32(v: &[i32]) -> PackedInt32Array {
    let mut out = PackedInt32Array::new();
    out.resize(v.len());
    for (i, x) in v.iter().enumerate() {
        out[i] = *x;
    }
    out
}

fn vec_to_packed_byte(v: &[u8]) -> PackedByteArray {
    let mut out = PackedByteArray::new();
    out.resize(v.len());
    for (i, x) in v.iter().enumerate() {
        out[i] = *x;
    }
    out
}

fn vec_to_packed_f32(v: &[f32]) -> PackedFloat32Array {
    let mut out = PackedFloat32Array::new();
    out.resize(v.len());
    for (i, x) in v.iter().enumerate() {
        out[i] = *x;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn txn_path_built_is_not_empty_after_push() {
        let mut txn = PresentationTxn::default();
        assert!(txn.is_empty());
        txn.push_path_built(3, 5.0);
        assert!(!txn.is_empty());
        assert_eq!(txn.path_built_sids, vec![3]);
        assert_eq!(txn.path_built_vals, vec![5.0]);
        let taken = txn.take();
        assert!(txn.is_empty());
        assert_eq!(taken.path_built_sids, vec![3]);
    }
}
