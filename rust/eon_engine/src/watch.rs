//! Watch pose view — mix two bake pages into Godot MultiMesh buffers.
//!
//! Combat authority stays in [`crate::battle`]. This module is presentation packing only:
//! GDScript must not walk 10k bodies to lerp. Tracers still spawn in the viewer from the
//! compact fire list this returns.

use crate::battle::{
    Frame, UnitSnapshot, BATTLE_HEIGHT, BATTLE_WIDTH, ST_AIM, ST_DEAD, ST_FIRE, ST_FLED, ST_HIT,
    ST_MARCH, ST_ROUT,
};
use crate::model::UnitKind;

pub const BUCKETS: usize = 16;
pub const BUF_STRIDE: usize = 16;
const SCALE: f32 = 1.0;
const GROUND_Y: f32 = 0.0;
const HIT_FLASH: f32 = 0.10;

pub const SHOT_NONE: u8 = 0;
pub const SHOT_RIFLE: u8 = 1;
pub const SHOT_HEAT: u8 = 2;
pub const SHOT_SATCHEL: u8 = 3;
pub const SHOT_SHELL: u8 = 4;
pub const SHOT_FLAK: u8 = 5;
pub const SHOT_BOMB: u8 = 6;

/// Per-body slot into a kind×faction MultiMesh (mirrors `BattleKinds.bucket_id` + BattleView).
#[derive(Clone, Debug)]
pub struct WatchLayout {
    pub n: usize,
    pub bucket: Vec<u8>,
    pub off: Vec<usize>,
    pub size: Vec<f32>,
    pub style: Vec<u8>,
    pub sheet_cols: Vec<u8>,
    pub uses_sheet: Vec<u8>,
    pub kind: Vec<u8>,
    pub bucket_count: [usize; BUCKETS],
}

#[derive(Clone, Copy, Debug)]
pub struct WatchFire {
    pub unit: u32,
    pub kind: u8,
    pub style: u8,
    pub from: [f32; 3],
    pub to: [f32; 3],
}

#[derive(Clone, Debug, Default)]
pub struct WatchFill {
    pub fire: Vec<WatchFire>,
    pub fire_n: u32,
    pub hit_n: u32,
    pub rout_n: u32,
}

pub fn bucket_id(kind: UnitKind, faction: u32) -> usize {
    (kind.as_u8() as usize).min(7) * 2 + (faction as usize & 1)
}

pub fn sprite_size(kind: UnitKind) -> f32 {
    match kind {
        UnitKind::Bomber => 5.2,
        UnitKind::LedgerPiece => 5.0,
        UnitKind::RollingHearth => 5.6,
        _ => 3.2,
    }
}

pub fn uses_sheet(kind: UnitKind) -> bool {
    matches!(
        kind,
        UnitKind::Soldier
            | UnitKind::Stovebreaker
            | UnitKind::AshWarden
            | UnitKind::WalkMapper
            | UnitKind::CeilingClerk
    )
}

pub fn sheet_cols(kind: UnitKind) -> u8 {
    match kind {
        UnitKind::LedgerPiece => 2,
        _ if uses_sheet(kind) => 8,
        _ => 1,
    }
}

pub fn shot_style(kind: UnitKind) -> u8 {
    match kind {
        UnitKind::Stovebreaker => SHOT_HEAT,
        UnitKind::AshWarden => SHOT_SATCHEL,
        UnitKind::LedgerPiece => SHOT_SHELL,
        UnitKind::RollingHearth => SHOT_NONE,
        UnitKind::CeilingClerk => SHOT_FLAK,
        UnitKind::Bomber => SHOT_BOMB,
        _ => SHOT_RIFLE,
    }
}

pub fn layout_units(units: &[UnitSnapshot]) -> WatchLayout {
    let n = units.len();
    let mut bucket = vec![0u8; n];
    let mut off = vec![0usize; n];
    let mut size = vec![3.2f32; n];
    let mut style = vec![0u8; n];
    let mut cols = vec![1u8; n];
    let mut sheet = vec![0u8; n];
    let mut kind = vec![0u8; n];
    let mut bucket_count = [0usize; BUCKETS];
    for (i, u) in units.iter().enumerate() {
        let id = bucket_id(u.kind, u.faction);
        bucket[i] = id as u8;
        off[i] = bucket_count[id] * BUF_STRIDE;
        bucket_count[id] += 1;
        size[i] = sprite_size(u.kind);
        style[i] = shot_style(u.kind);
        cols[i] = sheet_cols(u.kind);
        sheet[i] = u8::from(uses_sheet(u.kind));
        kind[i] = u.kind.as_u8();
    }
    WatchLayout {
        n,
        bucket,
        off,
        size,
        style,
        sheet_cols: cols,
        uses_sheet: sheet,
        kind,
        bucket_count,
    }
}

pub fn prepare_bufs(layout: &WatchLayout, bufs: &mut [Vec<f32>; BUCKETS]) {
    for id in 0..BUCKETS {
        let n = layout.bucket_count[id] * BUF_STRIDE;
        bufs[id].resize(n, 0.0);
        let sz = if layout.bucket_count[id] == 0 {
            3.2
        } else {
            sprite_size(UnitKind::from_u8((id / 2) as u8))
        };
        for k in 0..layout.bucket_count[id] {
            let o = k * BUF_STRIDE;
            bufs[id][o] = sz;
            bufs[id][o + 5] = sz;
            bufs[id][o + 10] = sz;
        }
    }
}

fn battle_to_world(px: f32, py: f32, w: f32, h: f32) -> (f32, f32) {
    let hw = w * 0.5;
    let hh = h * 0.5;
    ((px.clamp(0.0, w) - hw) * SCALE, (py.clamp(0.0, h) - hh) * SCALE)
}

fn pose_frame(
    cols: u8,
    i: usize,
    st: u8,
    firing: bool,
    dead: bool,
    frame_pos: f32,
) -> i32 {
    if cols < 2 {
        return 0;
    }
    if dead {
        return 0;
    }
    if cols == 2 {
        return i32::from(firing);
    }
    if firing {
        return 5 + ((frame_pos * 12.0).floor() as i32 + i as i32 * 2).rem_euclid(3);
    }
    if st == ST_HIT {
        return 0;
    }
    if st == ST_MARCH || st == ST_ROUT {
        return 1 + ((frame_pos * 8.0).floor() as i32 + i as i32).rem_euclid(4);
    }
    if st == ST_AIM {
        return 5;
    }
    0
}

fn write_instance(buf: &mut [f32], o: usize, szx: f32, szy: f32, wx: f32, yc: f32, wz: f32, packed: f32, fire: f32, dead: f32, fade: f32) {
    buf[o] = szx;
    buf[o + 5] = szy;
    buf[o + 10] = szx;
    buf[o + 3] = wx;
    buf[o + 7] = yc;
    buf[o + 11] = wz;
    buf[o + 12] = packed;
    buf[o + 13] = fire;
    buf[o + 14] = dead;
    buf[o + 15] = fade;
}

/// Mix bake pages at `frame_pos` into `bufs` (Godot TRANSFORM_3D + custom, stride 16).
pub fn fill_watch_pose(
    frames: &[Frame],
    layout: &WatchLayout,
    width: f32,
    height: f32,
    frame_pos: f32,
    lod: u8,
    hit_t: &[f32],
    bufs: &mut [Vec<f32>; BUCKETS],
) -> WatchFill {
    let mut out = WatchFill::default();
    if frames.is_empty() || layout.n == 0 {
        return out;
    }
    let last = frames.len().saturating_sub(1);
    let a = (frame_pos.floor() as usize).min(last);
    let b = (a + 1).min(last);
    let alpha = (frame_pos - a as f32).clamp(0.0, 1.0);
    let fa = &frames[a].units;
    let fb = &frames[b].units;
    let n = layout.n.min(fa.len());
    let w = if width > 1.0 { width } else { BATTLE_WIDTH };
    let h = if height > 1.0 { height } else { BATTLE_HEIGHT };

    for i in 0..n {
        let ua = &fa[i];
        let ub = if i < fb.len() { &fb[i] } else { ua };
        let st = ua.state;
        let st_b = ub.state;
        let dead = (!ua.alive) || st == ST_DEAD;
        let dying = ua.alive && (!ub.alive || st_b == ST_DEAD) && !dead;
        let fled_a = st == ST_FLED;
        let fled_b = st_b == ST_FLED;
        let firing = !dead && !fled_a && (st == ST_FIRE || st_b == ST_FIRE);
        let hit = !dead && (st == ST_HIT || st_b == ST_HIT);
        if firing {
            out.fire_n += 1;
        }
        if hit {
            out.hit_n += 1;
        }
        if st == ST_ROUT {
            out.rout_n += 1;
        }

        let facing = ua.facing;
        let flip = if (3..=5).contains(&facing) { 1.0 } else { 0.0 };
        let px = ua.x + (ub.x - ua.x) * alpha;
        let py = ua.y + (ub.y - ua.y) * alpha;
        let pz = ua.z + (ub.z - ua.z) * alpha;
        let (wx, wz) = battle_to_world(px, py, w, h);

        let mut base_sz = layout.size[i];
        let far = lod == 2 && layout.uses_sheet[i] != 0;
        if far {
            base_sz *= 0.82;
        }
        let mut szx = base_sz;
        let mut szy = base_sz;
        let mut fade = 1.0;
        if facing == 2 || facing == 6 {
            szx *= 0.72;
        } else if facing == 1 || facing == 3 || facing == 5 || facing == 7 {
            szx *= 0.86;
        }
        if fled_a && fled_b {
            fade = 0.0;
            szx = 0.0;
            szy = 0.0;
        } else if fled_b {
            fade = 1.0 - alpha;
            szx = base_sz * (0.35 + 0.65 * fade);
            szy = base_sz * (0.35 + 0.65 * fade);
        } else if fled_a {
            fade = 0.0;
            szx = 0.0;
            szy = 0.0;
        } else if dying {
            if pz > 0.55 {
                szx = base_sz * 0.92;
                szy = base_sz * 0.92;
            } else {
                szx = base_sz * 0.95;
                szy = base_sz * (1.0 - alpha) + (base_sz * 0.28) * alpha;
            }
        } else if dead {
            if pz > 0.55 {
                szx = base_sz * 0.92;
                szy = base_sz * 0.88;
            } else {
                szx = base_sz * 0.95;
                szy = base_sz * 0.28;
            }
        } else if i < hit_t.len() && hit_t[i] > HIT_FLASH * 0.35 {
            szy = base_sz * 0.90;
        } else if (st == ST_MARCH || st == ST_ROUT) && layout.sheet_cols[i] < 2 {
            let bob = 1.0 + 0.045 * (frame_pos * 9.0 + i as f32).sin();
            szy *= bob;
        }

        let mut yc = GROUND_Y + szy * 0.5 + pz * SCALE;
        if (dead || dying) && pz < 0.45 {
            yc = GROUND_Y + szy * 0.45;
        } else if fled_b && !fled_a {
            yc += (1.0 - fade) * 3.2;
        }

        let mut fire_ch = 0.0;
        if i < hit_t.len() && hit_t[i] > 0.0 {
            fire_ch = 0.28 + 0.32 * (hit_t[i] / HIT_FLASH);
        } else if hit {
            fire_ch = 0.42;
        }
        let corpse = if (dead || dying) && pz < 0.55 {
            1.0
        } else {
            0.0
        };
        let id = layout.bucket[i] as usize;
        let o = layout.off[i];
        let packed = (pose_frame(
            layout.sheet_cols[i],
            i,
            st,
            firing,
            corpse > 0.5,
            frame_pos,
        ) * 2) as f32
            + if flip > 0.5 { 1.0 } else { 0.0 };
        write_instance(
            &mut bufs[id],
            o,
            szx,
            szy,
            wx,
            yc,
            wz,
            packed,
            fire_ch,
            corpse,
            fade,
        );

        if firing && layout.style[i] != SHOT_NONE {
            let tx = ua.aim_x;
            let ty = ua.aim_y;
            if tx.abs() + ty.abs() > 1.0 {
                let mut tz = ua.aim_z;
                if i < fb.len() {
                    tz = ua.aim_z + (ub.aim_z - ua.aim_z) * alpha;
                }
                let style = layout.style[i];
                let (twx, twz) = battle_to_world(tx, ty, w, h);
                let mut tyw = GROUND_Y + 0.9;
                if style == SHOT_BOMB {
                    tyw = GROUND_Y + 0.35;
                } else if tz > 1.0 {
                    tyw = GROUND_Y + tz * SCALE;
                } else if style == SHOT_SHELL {
                    tyw = GROUND_Y + 0.55;
                }
                out.fire.push(WatchFire {
                    unit: i as u32,
                    kind: layout.kind[i],
                    style,
                    from: [wx, yc + 0.4, wz],
                    to: [twx, tyw, twz],
                });
            }
        }
    }
    out
}

pub fn origin_at(buf: &[f32], off: usize) -> (f32, f32, f32) {
    (buf[off + 3], buf[off + 7], buf[off + 11])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::battle::ST_IDLE;
    use crate::model::UnitKind;

    fn snap(
        fac: u32,
        kind: UnitKind,
        x: f32,
        y: f32,
        z: f32,
        alive: bool,
        state: u8,
    ) -> UnitSnapshot {
        UnitSnapshot {
            faction: fac,
            kind,
            x,
            y,
            z,
            alive,
            facing: if fac == 0 { 0 } else { 4 },
            state,
            aim_x: 0.0,
            aim_y: 0.0,
            aim_z: 0.0,
        }
    }

    fn two_pages(a: UnitSnapshot, b: UnitSnapshot) -> Vec<Frame> {
        vec![
            Frame {
                tick: 0,
                units: vec![a],
            },
            Frame {
                tick: 3,
                units: vec![b],
            },
        ]
    }

    fn posed(frames: &[Frame], t: f32) -> ([Vec<f32>; BUCKETS], WatchLayout, WatchFill) {
        let layout = layout_units(&frames[0].units);
        let mut bufs: [Vec<f32>; BUCKETS] = std::array::from_fn(|_| Vec::new());
        prepare_bufs(&layout, &mut bufs);
        let fill = fill_watch_pose(
            frames,
            &layout,
            BATTLE_WIDTH,
            BATTLE_HEIGHT,
            t,
            0,
            &[],
            &mut bufs,
        );
        (bufs, layout, fill)
    }

    #[test]
    fn alpha_zero_matches_page_a_world_x() {
        let a = snap(0, UnitKind::Soldier, 100.0, 300.0, 0.0, true, ST_IDLE);
        let b = snap(0, UnitKind::Soldier, 180.0, 300.0, 0.0, true, ST_MARCH);
        let frames = two_pages(a, b);
        let (bufs, layout, _) = posed(&frames, 0.0);
        let (wx, _yc, _wz) = origin_at(&bufs[layout.bucket[0] as usize], layout.off[0]);
        let (expect, _) = battle_to_world(100.0, 300.0, BATTLE_WIDTH, BATTLE_HEIGHT);
        assert!((wx - expect).abs() < 0.01, "wx={wx} expect={expect}");
    }

    #[test]
    fn alpha_one_matches_page_b_world_x() {
        let a = snap(0, UnitKind::Soldier, 100.0, 300.0, 0.0, true, ST_IDLE);
        let b = snap(0, UnitKind::Soldier, 180.0, 300.0, 0.0, true, ST_MARCH);
        let frames = two_pages(a, b);
        let (bufs, layout, _) = posed(&frames, 1.0);
        let (wx, _, _) = origin_at(&bufs[layout.bucket[0] as usize], layout.off[0]);
        let (expect, _) = battle_to_world(180.0, 300.0, BATTLE_WIDTH, BATTLE_HEIGHT);
        assert!((wx - expect).abs() < 0.01, "wx={wx} expect={expect}");
    }

    #[test]
    fn midpoint_is_halfway() {
        let a = snap(0, UnitKind::Soldier, 0.0, 300.0, 0.0, true, ST_MARCH);
        let b = snap(0, UnitKind::Soldier, 100.0, 300.0, 0.0, true, ST_MARCH);
        let frames = two_pages(a, b);
        let (bufs, layout, _) = posed(&frames, 0.5);
        let (wx, _, _) = origin_at(&bufs[layout.bucket[0] as usize], layout.off[0]);
        let (e0, _) = battle_to_world(100.0, 300.0, BATTLE_WIDTH, BATTLE_HEIGHT);
        let (e1, _) = battle_to_world(0.0, 300.0, BATTLE_WIDTH, BATTLE_HEIGHT);
        let mid = (e0 + e1) * 0.5;
        assert!((wx - mid).abs() < 0.02, "wx={wx} mid={mid}");
    }

    #[test]
    fn fled_both_pages_are_hidden() {
        let a = snap(1, UnitKind::Soldier, 50.0, 40.0, 0.0, true, ST_FLED);
        let b = snap(1, UnitKind::Soldier, 50.0, 40.0, 0.0, true, ST_FLED);
        let frames = two_pages(a, b);
        let (bufs, layout, _) = posed(&frames, 0.3);
        let id = layout.bucket[0] as usize;
        let o = layout.off[0];
        assert_eq!(bufs[id][o], 0.0);
        assert_eq!(bufs[id][o + 15], 0.0);
    }

    #[test]
    fn factions_land_in_separate_buckets() {
        let units = vec![
            snap(0, UnitKind::Soldier, 10.0, 10.0, 0.0, true, ST_IDLE),
            snap(1, UnitKind::Soldier, 20.0, 10.0, 0.0, true, ST_IDLE),
        ];
        let layout = layout_units(&units);
        assert_eq!(layout.bucket[0], 0);
        assert_eq!(layout.bucket[1], 1);
        assert_eq!(layout.bucket_count[0], 1);
        assert_eq!(layout.bucket_count[1], 1);
    }

    #[test]
    fn ten_thousand_mix_is_cheap() {
        let n = 10_000;
        let mut a = Vec::with_capacity(n);
        let mut b = Vec::with_capacity(n);
        for i in 0..n {
            let fac = (i % 2) as u32;
            let x = (i as f32) * 0.05;
            a.push(snap(fac, UnitKind::Soldier, x, 200.0, 0.0, true, ST_MARCH));
            b.push(snap(
                fac,
                UnitKind::Soldier,
                x + 4.0,
                200.0,
                0.0,
                true,
                ST_FIRE,
            ));
        }
        let frames = vec![
            Frame {
                tick: 0,
                units: a,
            },
            Frame {
                tick: 3,
                units: b,
            },
        ];
        let layout = layout_units(&frames[0].units);
        let mut bufs: [Vec<f32>; BUCKETS] = std::array::from_fn(|_| Vec::new());
        prepare_bufs(&layout, &mut bufs);
        let t0 = std::time::Instant::now();
        let fill = fill_watch_pose(
            &frames,
            &layout,
            BATTLE_WIDTH,
            BATTLE_HEIGHT,
            0.4,
            2,
            &[],
            &mut bufs,
        );
        let ms = t0.elapsed().as_secs_f64() * 1000.0;
        assert!(fill.fire_n > 0);
        assert!(
            ms < 40.0,
            "10k rust pose mix took {ms:.1}ms (should be a few ms)"
        );
    }

    #[test]
    fn line_volley_keeps_every_tracer_at_far_lod() {
        let n = 80;
        let mut units = Vec::with_capacity(n);
        for i in 0..n {
            let y = i as f32 * 4.0;
            let mut s = snap(0, UnitKind::Soldier, 100.0, y, 0.0, true, ST_FIRE);
            s.aim_x = 140.0;
            s.aim_y = y;
            units.push(s);
        }
        let frames = vec![
            Frame {
                tick: 0,
                units: units.clone(),
            },
            Frame {
                tick: 3,
                units,
            },
        ];
        let layout = layout_units(&frames[0].units);
        let mut bufs: [Vec<f32>; BUCKETS] = std::array::from_fn(|_| Vec::new());
        prepare_bufs(&layout, &mut bufs);
        let fill = fill_watch_pose(
            &frames,
            &layout,
            BATTLE_WIDTH,
            BATTLE_HEIGHT,
            0.0,
            2,
            &[],
            &mut bufs,
        );
        assert_eq!(fill.fire_n, n as u32);
        assert_eq!(
            fill.fire.len(),
            n,
            "far lod must not drop a Custom Battle line volley"
        );
    }
}
