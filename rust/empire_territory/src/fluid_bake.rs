//! Fluid display image bake (ports BattleTileFluidField._image_from_peak_power_grid).

const FLUID_ALPHA_PRESSURE_MAX: f32 = 100_000.0;
const DISPLAY_PRESSURE_REFERENCE: f32 = 10_000.0;
const FLUID_ALPHA_EXPONENT: f32 = 0.48;
const INTERIOR_FILL_ALPHA: f32 = 0.5;
const FRONT_LINE_ALPHA: f32 = 1.0;
const FRONT_RGB_BOOST: f32 = 1.35;
const DISPLAY_MIN_INTENSITY: f32 = 0.22;
const DISPLAY_NORMALIZE_PER_FRAME: bool = true;
const POWER_EPS: f32 = 0.01;

const TEAM_NONE: u8 = 0;
const TEAM_FRIENDLY: u8 = 1;
const TEAM_HOSTILE: u8 = 2;
const TEAM_TIE: u8 = 3;

const CARDINAL: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

fn dominant_team(friendly_power: f32, hostile_power: f32) -> u8 {
    let peak = friendly_power.max(hostile_power);
    if peak < POWER_EPS {
        return TEAM_NONE;
    }
    if friendly_power > hostile_power {
        TEAM_FRIENDLY
    } else if hostile_power > friendly_power {
        TEAM_HOSTILE
    } else {
        TEAM_TIE
    }
}

fn team_base_color(team: u8) -> (f32, f32, f32) {
    match team {
        TEAM_FRIENDLY => (0.18, 0.55, 0.95),
        TEAM_HOSTILE => (0.95, 0.32, 0.22),
        TEAM_TIE => (1.0, 0.85, 0.35),
        _ => (0.0, 0.0, 0.0),
    }
}

fn peak_intensity(peak: f32, power_scale: f32, frame_peak_max: f32) -> f32 {
    let pscale = power_scale.clamp(0.01, 1.0);
    if DISPLAY_NORMALIZE_PER_FRAME && frame_peak_max > 0.01 {
        let norm = (peak / frame_peak_max).clamp(0.0, 1.0);
        return (norm.powf(0.65) * pscale).clamp(DISPLAY_MIN_INTENSITY, 1.0);
    }
    let denom = FLUID_ALPHA_PRESSURE_MAX.max(1.0);
    (peak / denom).powf(FLUID_ALPHA_EXPONENT) * pscale
}

/// Bake RGBA8 bytes (w*h*4) from per-tile pressures.
/// Returns empty when grid dimensions do not match pressure/land arrays (e.g. graph cell_count vs 360×180).
pub fn bake_fluid_rgba(
    grid_w: i32,
    grid_h: i32,
    land_mask: &[u8],
    friendly_power: &[f32],
    hostile_power: &[f32],
    power_scale: f32,
) -> Vec<u8> {
    let w = grid_w as usize;
    let h = grid_h as usize;
    let n = w * h;
    if n == 0
        || land_mask.len() < n
        || friendly_power.len() < n
        || hostile_power.len() < n
    {
        return Vec::new();
    }

    let mut teams = vec![TEAM_NONE; n];
    let mut peaks = vec![0.0f32; n];
    let mut frame_peak_max = 0.0f32;

    for gy in 0..h {
        for gx in 0..w {
            let idx = gy * w + gx;
            if land_mask[idx] == 0 {
                continue;
            }
            let raw_pf = friendly_power.get(idx).copied().unwrap_or(0.0);
            let raw_ph = hostile_power.get(idx).copied().unwrap_or(0.0);
            peaks[idx] = raw_pf.max(raw_ph);
            teams[idx] = dominant_team(raw_pf, raw_ph);
            if peaks[idx] > frame_peak_max {
                frame_peak_max = peaks[idx];
            }
        }
    }

    let pressure_ref = if DISPLAY_NORMALIZE_PER_FRAME && frame_peak_max > 0.01 {
        frame_peak_max
    } else {
        DISPLAY_PRESSURE_REFERENCE
    };
    let _ = pressure_ref;

    let mut bytes = vec![0u8; n * 4];
    for gy in 0..h {
        for gx in 0..w {
            let idx = gy * w + gx;
            let bi = idx * 4;
            if land_mask[idx] == 0 {
                continue;
            }
            let team = teams[idx];
            if team == TEAM_NONE {
                continue;
            }
            let peak = peaks[idx];
            let intensity = peak_intensity(peak, power_scale, frame_peak_max);
            if intensity < 0.001 {
                continue;
            }

            let mut is_front = false;
            for (dx, dy) in CARDINAL {
                let nx = gx as i32 + dx;
                let ny = gy as i32 + dy;
                if nx < 0 || ny < 0 || nx >= grid_w || ny >= grid_h {
                    is_front = true;
                    break;
                }
                let ni = (ny as usize) * w + (nx as usize);
                if land_mask[ni] == 0 {
                    is_front = true;
                    break;
                }
                if teams[ni] != team {
                    is_front = true;
                    break;
                }
            }

            let (br, bg, bb) = team_base_color(team);
            let fill_alpha = if is_front {
                FRONT_LINE_ALPHA
            } else {
                INTERIOR_FILL_ALPHA
            } * intensity;
            let rgb_boost = if is_front { FRONT_RGB_BOOST } else { 1.0 };
            bytes[bi] = ((br * rgb_boost).clamp(0.0, 1.0) * 255.0) as u8;
            bytes[bi + 1] = ((bg * rgb_boost).clamp(0.0, 1.0) * 255.0) as u8;
            bytes[bi + 2] = ((bb * rgb_boost).clamp(0.0, 1.0) * 255.0) as u8;
            bytes[bi + 3] = (fill_alpha * 255.0) as u8;
        }
    }
    bytes
}
