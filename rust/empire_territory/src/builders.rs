//! Builder bots — **legacy only** (A6 / A7 / C8).
//!
//! Live World Conquest uses [`crate::logistics`] as the **sole** road / `path_built` authority.
//! Under live, FFI `configure_builders` / `builder_step` wire logistics only; this module must
//! not dual-step path growth.
//!
//! `BuilderLayer::step_frame` refuses to advance `path_built` unless
//! `legacy_path_growth_enabled` is explicitly set (unit tests / offline harnesses only).

use crate::sim::{OWNER_FRIENDLY, OWNER_HOSTILE};
use crate::structures::{
    has_build_phase, kind_to_str, StructureRecord, StructureStore, KIND_CORRIDOR_LINK,
    STATE_CONNECTING,
};

const STATE_IDLE: u8 = 0;
const STATE_WORKING: u8 = 1;
const STATE_RETURNING: u8 = 2;

#[derive(Clone, Debug)]
pub struct BuilderConfig {
    pub road_cells_per_sec: f32,
    pub bots_per_home: i32,
    pub orbit_radius_cells: f32,
    pub orbit_speed: f32,
    pub return_sec: f32,
    pub outpost_build_sec: f32,
    pub barracks_build_sec: f32,
    pub outpost_max_health: f32,
}

impl Default for BuilderConfig {
    fn default() -> Self {
        Self {
            road_cells_per_sec: 1.0,
            bots_per_home: 4,
            orbit_radius_cells: 3.5,
            orbit_speed: 0.55,
            return_sec: 0.45,
            outpost_build_sec: 5.0,
            barracks_build_sec: 5.0,
            outpost_max_health: 10.0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct BuilderBot {
    pub id: i32,
    pub team: u8,
    pub home_gx: i32,
    pub home_gy: i32,
    pub state: u8,
    pub job_sid: i32,
    pub seg_from_idx: i32,
    pub seg_t: f32,
    pub orbit_angle: f32,
    pub return_t: f32,
    pub return_gx_f: f32,
    pub return_gy_f: f32,
    pub chain_active: bool,
    pub chain_gx_f: f32,
    pub chain_gy_f: f32,
    pub chain_tx_f: f32,
    pub chain_ty_f: f32,
    pub chain_t: f32,
}

#[derive(Clone, Debug, Default)]
pub struct BuilderLayer {
    pub bots: Vec<BuilderBot>,
    pub queue_friendly: Vec<i32>,
    pub queue_hostile: Vec<i32>,
    pub player_home: (i32, i32),
    pub enemy_home: (i32, i32),
    /// When false (default), `step_frame` does **not** mutate `path_built` (logistics owns it).
    /// Set true only for legacy unit tests / offline builder harnesses.
    pub legacy_path_growth_enabled: bool,
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
pub struct BuilderStepEvents {
    pub visual_dirty: bool,
    pub cell_arrivals: Vec<CellArrivalEvent>,
    pub path_completions: Vec<PathCompletionEvent>,
    pub completed_corridor_sids: Vec<i32>,
    pub reassign_teams: Vec<u8>,
}

fn cell_travel_sec(cfg: &BuilderConfig) -> f32 {
    if cfg.road_cells_per_sec <= 0.001 {
        1.0
    } else {
        1.0 / cfg.road_cells_per_sec
    }
}

/// Unpack a packed gameplay cell key to `(gx, gy)`.
///
/// Live sphere WC passes `grid_w = cell_count` with a single-row layout (`grid_h = 1`), so
/// path keys are linear cell ids and this yields `(cell_key, 0)` for in-range keys. Rect maps
/// use standard row-major `(key % grid_w, key / grid_w)`. Callers must not pass overlay width
/// (360) as `grid_w` on sphere maps — use `cell_count` from the Rust backend config.
fn grid_from_packed_key(cell_key: i32, grid_w: i32) -> (i32, i32) {
    debug_assert!(grid_w > 0, "grid_from_packed_key: grid_w must be positive");
    (cell_key % grid_w, cell_key / grid_w)
}

fn path_len_from_record(st: &StructureRecord) -> i32 {
    if !st.path_keys.is_empty() {
        st.path_keys.len() as i32
    } else {
        st.path_len
    }
}

fn build_sec_for_kind(kind: u8, cfg: &BuilderConfig) -> f32 {
    if kind == crate::structures::KIND_BARRACKS || kind == crate::structures::KIND_HANGAR {
        cfg.barracks_build_sec
    } else {
        cfg.outpost_build_sec
    }
}

fn next_seg_index(path_built: f32) -> i32 {
    (path_built.floor() as i32 - 1).max(0)
}

fn path_built_after_seg(seg_from_idx: i32) -> f32 {
    (seg_from_idx + 2) as f32
}

fn orbit_grid(home_gx: i32, home_gy: i32, angle: f32, cfg: &BuilderConfig) -> (f32, f32) {
    let r = cfg.orbit_radius_cells;
    (
        home_gx as f32 + angle.cos() * r,
        home_gy as f32 + angle.sin() * r * 0.42,
    )
}

fn team_home(team: u8, layer: &BuilderLayer) -> (i32, i32) {
    if team == OWNER_HOSTILE {
        layer.enemy_home
    } else {
        layer.player_home
    }
}

fn find_structure<'a>(store: &'a StructureStore, sid: i32) -> Option<&'a StructureRecord> {
    if sid < 0 {
        return None;
    }
    store.structures.get(&sid)
}

fn job_queue_for_team_mut<'a>(layer: &'a mut BuilderLayer, team: u8) -> &'a mut Vec<i32> {
    if team == OWNER_HOSTILE {
        &mut layer.queue_hostile
    } else {
        &mut layer.queue_friendly
    }
}

fn job_queue_for_team<'a>(layer: &'a BuilderLayer, team: u8) -> &'a Vec<i32> {
    if team == OWNER_HOSTILE {
        &layer.queue_hostile
    } else {
        &layer.queue_friendly
    }
}

fn snap_pos_to_work_path(
    packed: &[i32],
    grid_w: i32,
    pos_x: f32,
    pos_y: f32,
    work_seg: i32,
) -> (i32, f32) {
    if packed.len() < 2 || work_seg >= (packed.len() as i32 - 1) {
        return (work_seg, 0.0);
    }
    let mut best_seg = work_seg;
    let mut best_t = 0.0_f32;
    let mut best_d2 = f32::INFINITY;
    for seg_idx in work_seg..(packed.len() as i32 - 1) {
        let (fx, fy) = grid_from_packed_key(packed[seg_idx as usize], grid_w);
        let (tx, ty) = grid_from_packed_key(packed[seg_idx as usize + 1], grid_w);
        let ax = fx as f32;
        let ay = fy as f32;
        let bx = tx as f32;
        let by = ty as f32;
        let abx = bx - ax;
        let aby = by - ay;
        let ab_len2 = abx * abx + aby * aby;
        let t = if ab_len2 > 0.0001 {
            ((pos_x - ax) * abx + (pos_y - ay) * aby) / ab_len2
        } else {
            0.0
        }
        .clamp(0.0, 1.0);
        let px = ax + (bx - ax) * t;
        let py = ay + (by - ay) * t;
        let dx = pos_x - px;
        let dy = pos_y - py;
        let d2 = dx * dx + dy * dy;
        if d2 < best_d2 {
            best_d2 = d2;
            best_seg = seg_idx;
            best_t = t;
        }
    }
    (best_seg, best_t)
}

pub fn work_grid_pos(
    bot: &BuilderBot,
    store: &StructureStore,
    grid_w: i32,
    cfg: &BuilderConfig,
    _layer: &BuilderLayer,
) -> (f32, f32) {
    match bot.state {
        STATE_IDLE => orbit_grid(bot.home_gx, bot.home_gy, bot.orbit_angle, cfg),
        STATE_RETURNING => {
            let ret_t = bot.return_t.clamp(0.0, 1.0);
            let orbit = orbit_grid(bot.home_gx, bot.home_gy, bot.orbit_angle, cfg);
            let from_x = bot.return_gx_f;
            let from_y = bot.return_gy_f;
            (
                from_x + (orbit.0 - from_x) * ret_t,
                from_y + (orbit.1 - from_y) * ret_t,
            )
        }
        STATE_WORKING if bot.chain_active => {
            let t = bot.chain_t.clamp(0.0, 1.0);
            (
                bot.chain_gx_f + (bot.chain_tx_f - bot.chain_gx_f) * t,
                bot.chain_gy_f + (bot.chain_ty_f - bot.chain_gy_f) * t,
            )
        }
        STATE_WORKING => {
            let Some(st) = find_structure(store, bot.job_sid) else {
                return orbit_grid(bot.home_gx, bot.home_gy, bot.orbit_angle, cfg);
            };
            let packed = &st.path_keys;
            let seg_idx = bot.seg_from_idx;
            if packed.len() < 2 || seg_idx >= (packed.len() as i32 - 1) || grid_w <= 0 {
                return (st.gx as f32, st.gy as f32);
            }
            let (fx, fy) = grid_from_packed_key(packed[seg_idx as usize], grid_w);
            let (tx, ty) =
                grid_from_packed_key(packed[(seg_idx + 1) as usize], grid_w);
            let t = bot.seg_t.clamp(0.0, 1.0);
            (
                fx as f32 + (tx - fx) as f32 * t,
                fy as f32 + (ty - fy) as f32 * t,
            )
        }
        _ => orbit_grid(bot.home_gx, bot.home_gy, bot.orbit_angle, cfg),
    }
}

impl BuilderLayer {
    pub fn clear(&mut self) {
        self.bots.clear();
        self.queue_friendly.clear();
        self.queue_hostile.clear();
    }

    pub fn init_bots(&mut self, cfg: &BuilderConfig) {
        self.bots.clear();
        let per_home = cfg.bots_per_home.max(1);
        let tau = std::f32::consts::TAU;
        for slot in 0..per_home {
            let angle = slot as f32 * tau / per_home as f32;
            self.bots.push(BuilderBot {
                id: slot,
                team: OWNER_FRIENDLY,
                home_gx: self.player_home.0,
                home_gy: self.player_home.1,
                state: STATE_IDLE,
                job_sid: -1,
                seg_from_idx: 0,
                seg_t: 0.0,
                orbit_angle: angle,
                return_t: 0.0,
                return_gx_f: 0.0,
                return_gy_f: 0.0,
                chain_active: false,
                chain_gx_f: 0.0,
                chain_gy_f: 0.0,
                chain_tx_f: 0.0,
                chain_ty_f: 0.0,
                chain_t: 0.0,
            });
        }
        for slot in 0..per_home {
            let angle = slot as f32 * tau / per_home as f32;
            self.bots.push(BuilderBot {
                id: slot,
                team: OWNER_HOSTILE,
                home_gx: self.enemy_home.0,
                home_gy: self.enemy_home.1,
                state: STATE_IDLE,
                job_sid: -1,
                seg_from_idx: 0,
                seg_t: 0.0,
                orbit_angle: angle,
                return_t: 0.0,
                return_gx_f: 0.0,
                return_gy_f: 0.0,
                chain_active: false,
                chain_gx_f: 0.0,
                chain_gy_f: 0.0,
                chain_tx_f: 0.0,
                chain_ty_f: 0.0,
                chain_t: 0.0,
            });
        }
    }

    pub fn enqueue_job(&mut self, sid: i32, team: u8) {
        if sid < 0 {
            return;
        }
        let q = job_queue_for_team_mut(self, team);
        if !q.contains(&sid) {
            q.push(sid);
        }
    }

    pub fn cancel_job(
        &mut self,
        sid: i32,
        store: &StructureStore,
        grid_w: i32,
        cfg: &BuilderConfig,
    ) {
        self.queue_friendly.retain(|&x| x != sid);
        self.queue_hostile.retain(|&x| x != sid);
        let n = self.bots.len();
        for i in 0..n {
            if self.bots[i].job_sid == sid {
                begin_builder_return_by_idx(self, i, store, grid_w, cfg);
            }
        }
    }

    fn start_builder_job(&mut self, bot: &mut BuilderBot, sid: i32, store: &StructureStore) {
        let Some(st) = find_structure(store, sid) else {
            return;
        };
        bot.state = STATE_WORKING;
        bot.job_sid = sid;
        bot.seg_from_idx = next_seg_index(st.path_built);
        bot.seg_t = 0.0;
        bot.return_t = 0.0;
        bot.chain_active = false;
    }

    fn start_builder_job_chained(
        &self,
        bot: &mut BuilderBot,
        sid: i32,
        store: &StructureStore,
        grid_w: i32,
        cfg: &BuilderConfig,
    ) {
        let (from_x, from_y) = work_grid_pos(bot, store, grid_w, cfg, self);
        let Some(st) = find_structure(store, sid).cloned() else {
            return;
        };
        apply_bot_job_from_position(bot, sid, &st, from_x, from_y, grid_w, true);
    }

    pub fn assign_builder_jobs(
        &mut self,
        store: &StructureStore,
        grid_w: i32,
        cfg: &BuilderConfig,
        team_filter: i32,
    ) {
        let bot_count = self.bots.len();
        for bi in 0..bot_count {
            if self.bots[bi].state != STATE_IDLE {
                continue;
            }
            let team = self.bots[bi].team;
            if team_filter >= 0 && team as i32 != team_filter {
                continue;
            }
            let assigned_sid = {
                let q = job_queue_for_team_mut(self, team);
                let mut found = None;
                while let Some(&sid) = q.first() {
                    let valid = find_structure(store, sid)
                        .map(|st| st.state == STATE_CONNECTING)
                        .unwrap_or(false);
                    q.remove(0);
                    if valid {
                        found = Some(sid);
                        break;
                    }
                }
                found
            };
            let Some(sid) = assigned_sid else {
                continue;
            };
            let Some(st) = find_structure(store, sid).cloned() else {
                continue;
            };
            let (from_x, from_y) = {
                let bot = &self.bots[bi];
                work_grid_pos(bot, store, grid_w, cfg, self)
            };
            apply_bot_job_from_position(&mut self.bots[bi], sid, &st, from_x, from_y, grid_w, true);
        }
    }


    fn on_cell_arrival(
        store: &mut StructureStore,
        sid: i32,
        seg_from_idx: i32,
    ) -> Option<CellArrivalEvent> {
        let Some(st) = store.structures.get_mut(&sid) else {
            return None;
        };
        st.path_built = path_built_after_seg(seg_from_idx);
        Some(CellArrivalEvent {
            sid,
            seg_from_idx,
            kind: st.kind,
        })
    }

    fn on_path_completed(
        store: &mut StructureStore,
        sid: i32,
        cfg: &BuilderConfig,
    ) -> Option<PathCompletionEvent> {
        let Some(st) = store.structures.get_mut(&sid) else {
            return None;
        };
        let path_len = path_len_from_record(st);
        st.path_len = path_len;
        st.path_built = path_len as f32;
        let kind = st.kind;
        let is_corridor_link = kind == KIND_CORRIDOR_LINK;
        if !is_corridor_link {
            let build_sec = build_sec_for_kind(kind, cfg);
            st.state = crate::structures::STATE_BUILDING;
            st.build_remaining = build_sec;
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

    pub fn step_frame(
        &mut self,
        dt: f32,
        store: &mut StructureStore,
        grid_w: i32,
        cfg: &BuilderConfig,
    ) -> BuilderStepEvents {
        let mut result = BuilderStepEvents::default();
        if dt <= 0.0 || self.bots.is_empty() {
            return result;
        }
        // A6/A7/C8: logistics is sole path_built authority under live. Default is off.
        if !self.legacy_path_growth_enabled {
            // Optional visual orbit only — never advance corridors.
            for bot in &mut self.bots {
                if bot.state == STATE_IDLE {
                    bot.orbit_angle += cfg.orbit_speed * dt;
                }
            }
            return result;
        }
        let travel_sec = cell_travel_sec(cfg);
        let bot_count = self.bots.len();
        for bi in 0..bot_count {
            let mut reassign_team: Option<u8> = None;
            let mut job_finished = false;
            match self.bots[bi].state {
                STATE_IDLE => {
                    self.bots[bi].orbit_angle += cfg.orbit_speed * dt;
                    continue;
                }
                STATE_RETURNING => {
                    self.bots[bi].return_t += dt / cfg.return_sec.max(0.001);
                    result.visual_dirty = true;
                    if self.bots[bi].return_t >= 1.0 {
                        self.bots[bi].state = STATE_IDLE;
                        self.bots[bi].return_t = 0.0;
                        reassign_team = Some(self.bots[bi].team);
                    }
                    if let Some(team) = reassign_team {
                        if !result.reassign_teams.contains(&team) {
                            result.reassign_teams.push(team);
                        }
                    }
                    continue;
                }
                STATE_WORKING => {}
                _ => continue,
            }
            if self.bots[bi].chain_active {
                self.bots[bi].chain_t += dt / travel_sec.max(0.001);
                result.visual_dirty = true;
                if self.bots[bi].chain_t < 1.0 {
                    continue;
                }
                self.bots[bi].chain_active = false;
            }
            let job_sid = self.bots[bi].job_sid;
            let st_valid = find_structure(store, job_sid)
                .map(|st| st.state == STATE_CONNECTING)
                .unwrap_or(false);
            if !st_valid {
                let team_bad = self.bots[bi].team;
                if !try_assign_next_job(self, bi, store, grid_w, cfg) {
                    reassign_team = Some(team_bad);
                }
                result.visual_dirty = true;
                if let Some(team) = reassign_team {
                    if !result.reassign_teams.contains(&team) {
                        result.reassign_teams.push(team);
                    }
                }
                continue;
            }
            let packed_len = find_structure(store, job_sid)
                .map(|st| st.path_keys.len())
                .unwrap_or(0);
            let seg_idx_start = self.bots[bi].seg_from_idx;
            if packed_len < 2 || seg_idx_start >= (packed_len as i32 - 1) {
                if let Some(done) = Self::on_path_completed(store, job_sid, cfg) {
                    if done.is_corridor_link {
                        result.completed_corridor_sids.push(done.sid);
                    }
                    result.path_completions.push(done);
                }
                let team_done = self.bots[bi].team;
                if !try_assign_next_job(self, bi, store, grid_w, cfg) {
                    reassign_team = Some(team_done);
                }
                result.visual_dirty = true;
                if let Some(team) = reassign_team {
                    if !result.reassign_teams.contains(&team) {
                        result.reassign_teams.push(team);
                    }
                }
                continue;
            }
            let mut seg_idx = self.bots[bi].seg_from_idx;
            let mut seg_t = self.bots[bi].seg_t + dt / travel_sec.max(0.001);
            while seg_t >= 1.0 {
                seg_t -= 1.0;
                if let Some(ev) = Self::on_cell_arrival(store, job_sid, seg_idx) {
                    result.cell_arrivals.push(ev);
                }
                let (path_len, built) = {
                    let Some(st) = store.structures.get(&job_sid) else {
                        break;
                    };
                    (path_len_from_record(st), st.path_built)
                };
                if built >= path_len as f32 {
                    if let Some(done) = Self::on_path_completed(store, job_sid, cfg) {
                        if done.is_corridor_link {
                            result.completed_corridor_sids.push(done.sid);
                        }
                        result.path_completions.push(done);
                    }
                    let team_full = self.bots[bi].team;
                    if !try_assign_next_job(self, bi, store, grid_w, cfg) {
                        reassign_team = Some(team_full);
                    }
                    job_finished = true;
                    break;
                }
                seg_idx += 1;
                let packed_len_now = store
                    .structures
                    .get(&job_sid)
                    .map(|st| st.path_keys.len())
                    .unwrap_or(0);
                if seg_idx >= (packed_len_now as i32 - 1) {
                    if let Some(done) = Self::on_path_completed(store, job_sid, cfg) {
                        if done.is_corridor_link {
                            result.completed_corridor_sids.push(done.sid);
                        }
                        result.path_completions.push(done);
                    }
                    let team_seg = self.bots[bi].team;
                    if !try_assign_next_job(self, bi, store, grid_w, cfg) {
                        reassign_team = Some(team_seg);
                    }
                    job_finished = true;
                    break;
                }
            }
            if job_finished {
                result.visual_dirty = true;
                if let Some(team) = reassign_team {
                    if !result.reassign_teams.contains(&team) {
                        result.reassign_teams.push(team);
                    }
                }
                continue;
            }
            self.bots[bi].seg_from_idx = seg_idx;
            self.bots[bi].seg_t = seg_t;
            result.visual_dirty = true;
        }
        for team in result.reassign_teams.clone() {
            self.assign_builder_jobs(store, grid_w, cfg, team as i32);
        }
        result
    }
}

fn try_assign_next_job(
    layer: &mut BuilderLayer,
    bot_idx: usize,
    store: &StructureStore,
    grid_w: i32,
    cfg: &BuilderConfig,
) -> bool {
    let team = layer.bots[bot_idx].team;
    let q = job_queue_for_team_mut(layer, team);
    while let Some(sid) = q.first().copied() {
        let valid = find_structure(store, sid)
            .map(|st| st.state == STATE_CONNECTING)
            .unwrap_or(false);
        q.remove(0);
        if !valid {
            continue;
        }
        let (from_x, from_y) = work_grid_pos(&layer.bots[bot_idx], store, grid_w, cfg, layer);
        let Some(st) = find_structure(store, sid).cloned() else {
            return false;
        };
        apply_bot_job_from_position(
            &mut layer.bots[bot_idx],
            sid,
            &st,
            from_x,
            from_y,
            grid_w,
            true,
        );
        return true;
    }
    begin_builder_return_by_idx(layer, bot_idx, store, grid_w, cfg);
    false
}

fn apply_bot_job_from_position(
    bot: &mut BuilderBot,
    sid: i32,
    st: &StructureRecord,
    from_x: f32,
    from_y: f32,
    grid_w: i32,
    allow_chain: bool,
) {
    bot.state = STATE_WORKING;
    bot.job_sid = sid;
    bot.return_t = 0.0;
    bot.chain_active = false;
    let packed = &st.path_keys;
    let work_seg = next_seg_index(st.path_built);
    if packed.len() < 2 || work_seg >= (packed.len() as i32 - 1) || grid_w <= 0 {
        bot.seg_from_idx = work_seg;
        bot.seg_t = 0.0;
        return;
    }
    let (seg_idx, seg_t) = snap_pos_to_work_path(packed, grid_w, from_x, from_y, work_seg);
    bot.seg_from_idx = seg_idx;
    bot.seg_t = seg_t;
    if !allow_chain {
        return;
    }
    let (fx, fy) = grid_from_packed_key(packed[seg_idx as usize], grid_w);
    let tx = fx as f32;
    let ty = fy as f32;
    let dx = from_x - tx;
    let dy = from_y - ty;
    if dx * dx + dy * dy > 0.01 {
        bot.chain_gx_f = from_x;
        bot.chain_gy_f = from_y;
        bot.chain_tx_f = tx;
        bot.chain_ty_f = ty;
        bot.chain_t = 0.0;
        bot.chain_active = true;
        bot.seg_t = 0.0;
    }
}

fn begin_builder_return_by_idx(
    layer: &mut BuilderLayer,
    bot_idx: usize,
    store: &StructureStore,
    grid_w: i32,
    cfg: &BuilderConfig,
) {
    let (pos_x, pos_y) = work_grid_pos(&layer.bots[bot_idx], store, grid_w, cfg, layer);
    let bot = &mut layer.bots[bot_idx];
    bot.return_gx_f = pos_x;
    bot.return_gy_f = pos_y;
    bot.state = STATE_RETURNING;
    bot.job_sid = -1;
    bot.seg_t = 0.0;
    bot.return_t = 0.0;
    bot.chain_active = false;
}

pub fn kind_str(kind: u8) -> &'static str {
    kind_to_str(kind)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::structures::{KIND_SPAWNER, StructureRecord};

    #[test]
    fn builder_selfcheck_connecting_to_building() {
        let mut layer = BuilderLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            // Explicit opt-in: unit test exercises legacy path growth only.
            legacy_path_growth_enabled: true,
            ..Default::default()
        };
        let cfg = BuilderConfig::default();
        layer.init_bots(&cfg);
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 1,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 3,
            gy: 0,
            path_keys: vec![0, 1, 2, 3],
            path_built: 1.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
            version: 0,
        });
        store.ready = true;
        layer.enqueue_job(1, OWNER_FRIENDLY);
        layer.assign_builder_jobs(&store, 16, &cfg, -1);
        let dt = 1.0 / 60.0;
        let mut cells = 0;
        for _ in 0..2400 {
            let frame = layer.step_frame(dt, &mut store, 16, &cfg);
            cells += frame.cell_arrivals.len();
            if store.structures.get(&1).map(|s| s.state).unwrap_or(STATE_CONNECTING)
                == crate::structures::STATE_ACTIVE
                || store.structures.get(&1).map(|s| s.state).unwrap_or(STATE_CONNECTING)
                    == crate::structures::STATE_BUILDING
            {
                assert!(
                    cells >= 1 || store.structures.get(&1).unwrap().path_built >= 4.0,
                    "legacy growth should advance path or complete with arrivals"
                );
                return;
            }
        }
        panic!("builder selfcheck stuck");
    }

    #[test]
    fn builders_do_not_advance_path_built_when_legacy_growth_disabled() {
        let mut layer = BuilderLayer {
            player_home: (0, 0),
            enemy_home: (8, 8),
            legacy_path_growth_enabled: false,
            ..Default::default()
        };
        let cfg = BuilderConfig::default();
        layer.init_bots(&cfg);
        let mut store = StructureStore::default();
        store.upsert(StructureRecord {
            id: 1,
            team: OWNER_FRIENDLY,
            kind: KIND_SPAWNER,
            state: STATE_CONNECTING,
            gx: 3,
            gy: 0,
            path_keys: vec![0, 1, 2, 3],
            path_built: 1.0,
            path_len: 4,
            corridor_synced_built: 0,
            health: -1.0,
            build_remaining: -1.0,
            spawn_timer: 0.0,
            version: 0,
        });
        store.ready = true;
        layer.enqueue_job(1, OWNER_FRIENDLY);
        layer.assign_builder_jobs(&store, 16, &cfg, -1);
        for _ in 0..120 {
            let frame = layer.step_frame(1.0 / 60.0, &mut store, 16, &cfg);
            assert!(
                frame.cell_arrivals.is_empty(),
                "legacy-disabled builders must not emit path growth"
            );
        }
        assert_eq!(
            store.structures.get(&1).unwrap().path_built,
            1.0,
            "path_built must stay untouched when logistics is the authority"
        );
    }
}
