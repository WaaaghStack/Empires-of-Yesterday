//! Pressure tape codec and EYTR v2 pack helpers.

const MAX_PRESSURE_V2: f32 = 10_000.0;
const MAGIC: &[u8] = b"EYTR";
const VERSION_V2: u8 = 2;
const HEADER_SIZE: usize = 24;
const FRAME_SECONDS: f32 = 0.5;

pub fn encode_pressure_v2(pressure: &[f32]) -> Vec<u8> {
    let log_denom = (1.0 + MAX_PRESSURE_V2).ln();
    let mut out = Vec::with_capacity(pressure.len());
    for &p in pressure {
        let p = p.max(0.0);
        let t = ((1.0 + p).ln() / log_denom).clamp(0.0, 1.0);
        out.push((t * 255.0).round() as u8);
    }
    out
}

pub fn decode_pressure_v2(blob: &[u8]) -> Vec<f32> {
    let log_denom = (1.0 + MAX_PRESSURE_V2).ln();
    blob.iter()
        .map(|&b| {
            let t = b as f32 / 255.0;
            (t * log_denom).exp() - 1.0
        })
        .collect()
}

/// Pack a territory tape blob (EYTR v2). Frame data passed as parallel arrays per frame.
pub fn pack_territory_tape_v2(
    grid_w: u16,
    grid_h: u16,
    record_stride: u16,
    frame_count: u32,
    frame_rounds: &[u32],
    frame_friendly: &[u16],
    frame_hostile: &[u16],
    frame_full_flags: &[u8],
    frame_owner_full: &[Vec<u8>],
    frame_owner_deltas: &[Vec<(u16, u8)>],
    frame_pressure_f: &[Vec<u8>],
    frame_pressure_h: &[Vec<u8>],
) -> Vec<u8> {
    let cells = grid_w as usize * grid_h as usize;
    if cells == 0 || frame_count == 0 {
        return Vec::new();
    }

    let mut body = Vec::new();
    for fi in 0..frame_count as usize {
        body.extend_from_slice(&frame_rounds[fi].to_le_bytes());
        body.extend_from_slice(&frame_friendly[fi].to_le_bytes());
        body.extend_from_slice(&frame_hostile[fi].to_le_bytes());
        body.push(frame_full_flags[fi]);
        body.push(2); // pressure_codec v2
        body.extend_from_slice(&0u16.to_le_bytes());

        if frame_full_flags[fi] != 0 {
            let owners = &frame_owner_full[fi];
            let copy_len = owners.len().min(cells);
            body.extend_from_slice(&owners[..copy_len]);
            if copy_len < cells {
                body.resize(body.len() + (cells - copy_len), 0);
            }
        } else {
            let deltas = &frame_owner_deltas[fi];
            body.extend_from_slice(&(deltas.len() as u16).to_le_bytes());
            for &(idx, owner) in deltas {
                body.extend_from_slice(&idx.to_le_bytes());
                body.push(owner);
            }
        }

        let pf = &frame_pressure_f[fi];
        let ph = &frame_pressure_h[fi];
        let pf_len = pf.len().min(cells);
        let ph_len = ph.len().min(cells);
        body.extend_from_slice(&pf[..pf_len]);
        if pf_len < cells {
            body.resize(body.len() + (cells - pf_len), 0);
        }
        body.extend_from_slice(&ph[..ph_len]);
        if ph_len < cells {
            body.resize(body.len() + (cells - ph_len), 0);
        }
    }

    let mut hdr = Vec::with_capacity(HEADER_SIZE);
    hdr.extend_from_slice(MAGIC);
    hdr.push(VERSION_V2);
    hdr.extend_from_slice(&[0u8; 3]);
    hdr.extend_from_slice(&frame_count.to_le_bytes());
    hdr.extend_from_slice(&grid_w.to_le_bytes());
    hdr.extend_from_slice(&grid_h.to_le_bytes());
    hdr.extend_from_slice(&record_stride.max(1).to_le_bytes());
    hdr.extend_from_slice(&0u16.to_le_bytes());
    hdr.extend_from_slice(&FRAME_SECONDS.to_le_bytes());

    let mut out = hdr;
    out.extend_from_slice(&body);
    out
}
