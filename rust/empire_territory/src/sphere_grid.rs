//! Equal-area spherical cell grid via subdivided icosahedron (geodesic).

use std::collections::{HashMap, HashSet};

const TAU: f32 = std::f32::consts::TAU;
const PI: f32 = std::f32::consts::PI;

#[derive(Clone, Debug)]
pub struct SphereGrid {
    pub frequency: u32,
    pub cell_count: usize,
    /// Unit-sphere positions (x,y,z) per cell
    pub positions: Vec<[f32; 3]>,
    /// lat radians per cell
    pub lat: Vec<f32>,
    /// lon radians per cell (-PI..PI)
    pub lon: Vec<f32>,
    /// Up to 6 neighbors; unused slots = -1
    pub neighbors: Vec<[i32; 6]>,
    /// 0..=6
    pub neighbor_count: Vec<u8>,
    /// Triangle faces as cell index triples (for mesh / dual viz)
    pub faces: Vec<[u32; 3]>,
}

impl SphereGrid {
    /// frequency >= 1. Target: frequency=80 → ~64002 cells.
    pub fn generate(frequency: u32) -> Self {
        assert!(frequency >= 1, "frequency must be >= 1");
        let f = frequency;

        let (base_verts, base_faces) = icosahedron();
        let mut positions = base_verts.clone();
        let mut edge_verts: HashMap<(u32, u32, u32), u32> = HashMap::new();
        let mut faces: Vec<[u32; 3]> = Vec::new();

        for face in &base_faces {
            let v0 = face[0];
            let v1 = face[1];
            let v2 = face[2];
            let p0 = base_verts[v0 as usize];
            let p1 = base_verts[v1 as usize];
            let p2 = base_verts[v2 as usize];

            let mut grid: Vec<Vec<u32>> =
                vec![vec![0; (f + 1) as usize]; (f + 1) as usize];

            for i in 0..=f {
                for j in 0..=(f - i) {
                    grid[i as usize][j as usize] = face_vertex(
                        &mut positions,
                        &mut edge_verts,
                        p0,
                        p1,
                        p2,
                        v0,
                        v1,
                        v2,
                        i,
                        j,
                        f,
                    );
                }
            }

            for i in 0..f {
                for j in 0..(f - i) {
                    let a = grid[i as usize][j as usize];
                    let b = grid[(i + 1) as usize][j as usize];
                    let c = grid[i as usize][(j + 1) as usize];
                    faces.push([a, b, c]);

                    if j < f - i - 1 {
                        let d = grid[(i + 1) as usize][(j + 1) as usize];
                        faces.push([b, d, c]);
                    }
                }
            }
        }

        let (neighbors, neighbor_count) = build_neighbors(positions.len(), &faces);
        // Edge sharing covers most dups; rare float collisions get an O(n) spatial nudge.
        separate_coincident_vertices_hashed(&mut positions);

        let cell_count = positions.len();
        let mut lat = Vec::with_capacity(cell_count);
        let mut lon = Vec::with_capacity(cell_count);
        for p in &positions {
            lat.push(p[1].clamp(-1.0, 1.0).asin());
            lon.push(p[2].atan2(p[0]));
        }

        Self {
            frequency: f,
            cell_count,
            positions,
            lat,
            lon,
            neighbors,
            neighbor_count,
            faces,
        }
    }

    /// Sample equirect land mask: land_bits length = src_w*src_h, row-major.
    /// Returns Vec<u8> length cell_count, 1=land.
    pub fn sample_land_mask(&self, land_bits: &[u8], src_w: u32, src_h: u32) -> Vec<u8> {
        (0..self.cell_count)
            .map(|i| {
                let idx = self.equirect_index(i, src_w, src_h);
                if land_bits.get(idx).copied().unwrap_or(0) != 0 {
                    1
                } else {
                    0
                }
            })
            .collect()
    }

    /// Sample equirect elevation floats length src_w*src_h.
    pub fn sample_elevation(&self, elev: &[f32], src_w: u32, src_h: u32) -> Vec<f32> {
        (0..self.cell_count)
            .map(|i| {
                let idx = self.equirect_index(i, src_w, src_h);
                elev.get(idx).copied().unwrap_or(0.0)
            })
            .collect()
    }

    /// Nearest cell to a unit direction (or any non-zero vec3).
    pub fn nearest_cell(&self, dir: [f32; 3]) -> i32 {
        for (i, p) in self.positions.iter().enumerate() {
            if p[0] == dir[0] && p[1] == dir[1] && p[2] == dir[2] {
                return i as i32;
            }
        }

        let d = normalize(dir);
        let mut best_i = 0i32;
        let mut best_dot = f32::NEG_INFINITY;
        for (i, p) in self.positions.iter().enumerate() {
            let pn = normalize(*p);
            let dot = d[0] * pn[0] + d[1] * pn[1] + d[2] * pn[2];
            if dot > best_dot {
                best_dot = dot;
                best_i = i as i32;
            }
        }
        best_i
    }

    fn equirect_index(&self, cell: usize, src_w: u32, src_h: u32) -> usize {
        let lon = self.lon[cell];
        let lat = self.lat[cell];
        let u = (lon + PI) / TAU * src_w as f32;
        let v = (PI / 2.0 - lat) / PI * src_h as f32;
        let gx = wrap_floor(u, src_w);
        let gy = clamp_floor(v, src_h);
        (gy * src_w + gx) as usize
    }

    /// Multi-source BFS Voronoi on equirect pixels — O(ow*oh + cells).
    /// Seeds each cell's lon/lat pixel, then 4-connected flood with lon wrap.
    pub fn build_equirect_to_cell(&self, ow: u32, oh: u32) -> Vec<i32> {
        if ow == 0 || oh == 0 {
            return Vec::new();
        }
        let total = (ow * oh) as usize;
        let mut result = vec![-1i32; total];
        let mut qx = vec![0i32; total];
        let mut qy = vec![0i32; total];
        let mut q_head = 0usize;
        let mut q_tail = 0usize;

        for (i, (&lon, &lat)) in self.lon.iter().zip(self.lat.iter()).enumerate() {
            let gx = wrap_floor((lon + PI) / TAU * ow as f32, ow);
            let gy = clamp_floor((PI / 2.0 - lat) / PI * oh as f32, oh);
            let pidx = (gy * ow + gx) as usize;
            if result[pidx] == -1 {
                result[pidx] = i as i32;
                qx[q_tail] = gx as i32;
                qy[q_tail] = gy as i32;
                q_tail += 1;
            }
        }

        let ow_i = ow as i32;
        let oh_i = oh as i32;
        while q_head < q_tail {
            let cx = qx[q_head];
            let cy = qy[q_head];
            q_head += 1;
            let cur_cell = result[(cy as u32 * ow + cx as u32) as usize];

            for di in 0..4 {
                let mut nx = cx;
                let mut ny = cy;
                match di {
                    0 => nx += 1,
                    1 => nx -= 1,
                    2 => ny += 1,
                    3 => ny -= 1,
                    _ => {}
                }
                if ny < 0 || ny >= oh_i {
                    continue;
                }
                if nx < 0 {
                    nx = ow_i - 1;
                } else if nx >= ow_i {
                    nx = 0;
                }
                let nidx = (ny as u32 * ow + nx as u32) as usize;
                if result[nidx] == -1 {
                    result[nidx] = cur_cell;
                    qx[q_tail] = nx;
                    qy[q_tail] = ny;
                    q_tail += 1;
                }
            }
        }

        result
    }
}

fn icosahedron() -> (Vec<[f32; 3]>, Vec<[u32; 3]>) {
    let t = (1.0 + 5.0_f32.sqrt()) / 2.0;
    let raw: [[f32; 3]; 12] = [
        [-1.0, t, 0.0],
        [1.0, t, 0.0],
        [-1.0, -t, 0.0],
        [1.0, -t, 0.0],
        [0.0, -1.0, t],
        [0.0, 1.0, t],
        [0.0, -1.0, -t],
        [0.0, 1.0, -t],
        [0.0, -t, 1.0],
        [0.0, t, 1.0],
        [0.0, -t, -1.0],
        [0.0, t, -1.0],
    ];
    let verts: Vec<[f32; 3]> = raw.iter().map(|v| normalize(*v)).collect();
    let faces: Vec<[u32; 3]> = vec![
        [0, 11, 5],
        [0, 5, 1],
        [0, 1, 7],
        [0, 7, 10],
        [0, 10, 11],
        [1, 5, 9],
        [5, 11, 4],
        [11, 10, 2],
        [10, 7, 6],
        [7, 1, 8],
        [3, 9, 4],
        [3, 4, 2],
        [3, 2, 6],
        [3, 6, 8],
        [3, 8, 9],
        [4, 9, 5],
        [2, 4, 11],
        [6, 2, 10],
        [8, 6, 7],
        [9, 8, 1],
    ];
    (verts, faces)
}

fn normalize(v: [f32; 3]) -> [f32; 3] {
    let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    if len <= 0.0 {
        return [0.0, 1.0, 0.0];
    }
    [v[0] / len, v[1] / len, v[2] / len]
}

fn slerp(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    let mut dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    dot = dot.clamp(-1.0, 1.0);
    let theta = dot.acos();
    if theta < 1e-6 {
        return normalize([
            a[0] * (1.0 - t) + b[0] * t,
            a[1] * (1.0 - t) + b[1] * t,
            a[2] * (1.0 - t) + b[2] * t,
        ]);
    }
    let sin_theta = theta.sin();
    let w1 = ((1.0 - t) * theta).sin() / sin_theta;
    let w2 = (t * theta).sin() / sin_theta;
    normalize([
        a[0] * w1 + b[0] * w2,
        a[1] * w1 + b[1] * w2,
        a[2] * w1 + b[2] * w2,
    ])
}

fn subdivide_edge(
    positions: &mut Vec<[f32; 3]>,
    edge_verts: &mut HashMap<(u32, u32, u32), u32>,
    a: u32,
    b: u32,
    step: u32,
    f: u32,
) -> u32 {
    if step == 0 {
        return a;
    }
    if step == f {
        return b;
    }
    let lo = a.min(b);
    let hi = a.max(b);
    let step_from_lo = if a == lo { step } else { f - step };
    let key = (lo, hi, step_from_lo);
    if let Some(&idx) = edge_verts.get(&key) {
        return idx;
    }
    let va = positions[lo as usize];
    let vb = positions[hi as usize];
    let pos = slerp(va, vb, step_from_lo as f32 / f as f32);
    let idx = positions.len() as u32;
    positions.push(pos);
    edge_verts.insert(key, idx);
    idx
}

fn face_vertex(
    positions: &mut Vec<[f32; 3]>,
    edge_verts: &mut HashMap<(u32, u32, u32), u32>,
    p0: [f32; 3],
    p1: [f32; 3],
    p2: [f32; 3],
    v0: u32,
    v1: u32,
    v2: u32,
    i: u32,
    j: u32,
    f: u32,
) -> u32 {
    if j == 0 {
        return subdivide_edge(positions, edge_verts, v0, v1, i, f);
    }
    if i == 0 {
        return subdivide_edge(positions, edge_verts, v0, v2, j, f);
    }
    if i + j == f {
        return subdivide_edge(positions, edge_verts, v1, v2, f - i, f);
    }

    let k = f - i - j;
    let pos = normalize([
        p0[0] * k as f32 + p1[0] * i as f32 + p2[0] * j as f32,
        p0[1] * k as f32 + p1[1] * i as f32 + p2[1] * j as f32,
        p0[2] * k as f32 + p1[2] * i as f32 + p2[2] * j as f32,
    ]);
    let idx = positions.len() as u32;
    positions.push(pos);
    idx
}

fn separate_coincident_vertices_hashed(positions: &mut [[f32; 3]]) {
    // Quantized spatial hash — O(n), not the old O(n²) exact-equality scan.
    let mut seen: HashMap<(i32, i32, i32), usize> = HashMap::with_capacity(positions.len());
    const Q: f32 = 1.0e6;
    for i in 0..positions.len() {
        let p = positions[i];
        let key = (
            (p[0] * Q).round() as i32,
            (p[1] * Q).round() as i32,
            (p[2] * Q).round() as i32,
        );
        if let Some(&j) = seen.get(&key) {
            let nudge = (i - j) as f32 * 1e-7;
            positions[i][0] += nudge;
            positions[i] = normalize(positions[i]);
        } else {
            seen.insert(key, i);
        }
    }
}

fn build_neighbors(cell_count: usize, faces: &[[u32; 3]]) -> (Vec<[i32; 6]>, Vec<u8>) {
    let mut adj: Vec<HashSet<u32>> = vec![HashSet::new(); cell_count];

    for tri in faces {
        let verts = [tri[0] as usize, tri[1] as usize, tri[2] as usize];
        for a in 0..3 {
            for b in (a + 1)..3 {
                let va = verts[a];
                let vb = verts[b];
                if va == vb {
                    continue;
                }
                adj[va].insert(vb as u32);
                adj[vb].insert(va as u32);
            }
        }
    }

    let mut neighbors = vec![[-1i32; 6]; cell_count];
    let mut neighbor_count = vec![0u8; cell_count];

    for (i, nbrs) in adj.iter().enumerate() {
        let mut list: Vec<u32> = nbrs.iter().copied().collect();
        list.sort_unstable();
        let count = list.len().min(6);
        neighbor_count[i] = count as u8;
        for (slot, &n) in list.iter().take(6).enumerate() {
            neighbors[i][slot] = n as i32;
        }
    }

    (neighbors, neighbor_count)
}

fn wrap_floor(u: f32, src_w: u32) -> u32 {
    let mut gx = u.floor() as i32;
    if src_w > 0 {
        gx = gx.rem_euclid(src_w as i32);
    }
    gx as u32
}

fn clamp_floor(v: f32, src_h: u32) -> u32 {
    if src_h == 0 {
        return 0;
    }
    let gy = v.floor() as i32;
    gy.clamp(0, src_h as i32 - 1) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_f1_has_12_verts() {
        let g = SphereGrid::generate(1);
        assert_eq!(g.cell_count, 12);
        assert_eq!(g.positions.len(), 12);
    }

    #[test]
    fn generate_f2_has_42_verts() {
        let g = SphereGrid::generate(2);
        assert_eq!(g.cell_count, 42);
    }

    #[test]
    fn generate_f8_has_642_verts() {
        let g = SphereGrid::generate(8);
        assert_eq!(g.cell_count, 642);
    }

    #[test]
    fn generate_f80_has_64002_verts() {
        let g = SphereGrid::generate(80);
        assert_eq!(g.cell_count, 64002);
    }

    #[test]
    fn neighbors_are_symmetric() {
        let g = SphereGrid::generate(4);
        for i in 0..g.cell_count {
            for slot in 0..g.neighbor_count[i] as usize {
                let j = g.neighbors[i][slot];
                assert!(j >= 0, "neighbor index must be non-negative");
                let j = j as usize;
                let mut found = false;
                for k in 0..g.neighbor_count[j] as usize {
                    if g.neighbors[j][k] == i as i32 {
                        found = true;
                        break;
                    }
                }
                assert!(found, "asymmetric neighbor: {i} -> {j} but not back");
            }
        }
    }

    #[test]
    fn neighbor_count_is_5_or_6() {
        let g = SphereGrid::generate(8);
        for (i, &nc) in g.neighbor_count.iter().enumerate() {
            assert!(
                nc == 5 || nc == 6,
                "cell {i} has neighbor_count {nc}, expected 5 or 6"
            );
        }
    }

    #[test]
    fn nearest_cell_returns_self() {
        let g = SphereGrid::generate(8);
        for i in 0..g.cell_count {
            let nearest = g.nearest_cell(g.positions[i]);
            assert_eq!(
                nearest, i as i32,
                "nearest_cell({i}) = {nearest}, expected {i}"
            );
        }
    }

    #[test]
    fn sample_land_mask_all_zero() {
        let g = SphereGrid::generate(4);
        let mask = vec![0u8; 64 * 32];
        let out = g.sample_land_mask(&mask, 64, 32);
        assert_eq!(out.len(), g.cell_count);
        assert!(out.iter().all(|&v| v == 0));
    }

    #[test]
    fn sample_land_mask_all_one() {
        let g = SphereGrid::generate(4);
        let mask = vec![1u8; 64 * 32];
        let out = g.sample_land_mask(&mask, 64, 32);
        assert_eq!(out.len(), g.cell_count);
        assert!(out.iter().all(|&v| v == 1));
    }

    #[test]
    fn build_equirect_to_cell_f2_36x18() {
        let g = SphereGrid::generate(2);
        let lut = g.build_equirect_to_cell(36, 18);
        assert_eq!(lut.len(), 36 * 18);
        for &cell in &lut {
            assert!(cell >= 0, "unassigned equirect pixel");
            assert!(
                (cell as usize) < g.cell_count,
                "cell id {cell} out of range (cell_count={})",
                g.cell_count
            );
        }
    }
}
