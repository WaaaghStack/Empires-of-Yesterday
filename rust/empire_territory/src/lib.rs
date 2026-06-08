//! Empire Territory Sim — Rust GDExtension for high-performance territory conquest simulation.

mod fluid_bake;
mod sim;
mod tape_codec;

use fluid_bake::bake_fluid_rgba;
use godot::builtin::Variant;
use godot::prelude::*;
use rayon::prelude::*;
use sim::{Spawner, TerritoryKernel};
use tape_codec::{decode_pressure_v2, encode_pressure_v2, pack_territory_tape_v2};

type GdDictionary = Dictionary<Variant, Variant>;

struct EmpireTerritoryExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EmpireTerritoryExtension {}

fn packed_byte_to_vec(arr: &PackedByteArray) -> Vec<u8> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(0)).collect()
}

fn packed_f32_to_vec(arr: &PackedFloat32Array) -> Vec<f32> {
    (0..arr.len()).map(|i| arr.get(i).unwrap_or(0.0)).collect()
}

fn vec_to_packed_byte(data: &[u8]) -> PackedByteArray {
    PackedByteArray::from(data)
}

fn vec_to_packed_f32(data: &[f32]) -> PackedFloat32Array {
    PackedFloat32Array::from(data)
}

fn spawners_from_dict(config: &GdDictionary) -> Vec<Spawner> {
    let teams = config
        .get("spawner_teams")
        .and_then(|v| v.try_to::<PackedByteArray>().ok())
        .unwrap_or_default();
    let gx = config
        .get("spawner_gx")
        .and_then(|v| v.try_to::<PackedInt32Array>().ok())
        .unwrap_or_default();
    let gy = config
        .get("spawner_gy")
        .and_then(|v| v.try_to::<PackedInt32Array>().ok())
        .unwrap_or_default();
    let count = teams.len().min(gx.len()).min(gy.len());
    let mut spawners = Vec::with_capacity(count);
    for i in 0..count {
        spawners.push(Spawner {
            team: teams.get(i).unwrap_or(0),
            gx: gx.get(i).unwrap_or(-1),
            gy: gy.get(i).unwrap_or(-1),
        });
    }
    spawners
}

/// Main simulation object exposed to GDScript.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct TerritorySim {
    base: Base<RefCounted>,
    kernel: Option<TerritoryKernel>,
}

#[godot_api]
impl TerritorySim {
    #[func]
    fn hello(&self) -> GString {
        "Hello from Rust (empire_territory) — simple water sim active.".into()
    }

    #[func]
    fn version(&self) -> GString {
        env!("CARGO_PKG_VERSION").into()
    }

    #[func]
    fn is_ready(&self) -> bool {
        self.kernel.is_some()
    }

    #[func]
    fn setup_from_dict(&mut self, config: GdDictionary) -> bool {
        let grid_w: i32 = config.get("grid_w").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let grid_h: i32 = config.get("grid_h").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let tile_count = (grid_w * grid_h) as usize;
        if tile_count <= 0 {
            self.kernel = None;
            return false;
        }

        let use_active_set: bool = config
            .get("use_active_set")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(false);
        let use_adaptive_double_pass: bool = config
            .get("use_adaptive_double_pass")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(!use_active_set);

        let claimable: PackedByteArray = config
            .get("claimable")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let elevation: PackedFloat32Array = config
            .get("elevation")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let flow_mult: PackedFloat32Array = config
            .get("flow_mult")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let claim_mult: PackedFloat32Array = config
            .get("claim_mult")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let owners: PackedByteArray = config
            .get("owners")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let pressure_friendly: PackedFloat32Array = config
            .get("pressure_friendly")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let pressure_hostile: PackedFloat32Array = config
            .get("pressure_hostile")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();

        let friendly_spawn_rate: f32 = config
            .get("friendly_spawn_rate")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0.0);
        let hostile_spawn_rate: f32 = config
            .get("hostile_spawn_rate")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0.0);
        let player_home_idx: i32 = config
            .get("player_home_idx")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(-1);
        let enemy_home_idx: i32 = config
            .get("enemy_home_idx")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(-1);
        let friendly_tiles: i32 = config
            .get("friendly_tiles")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        let hostile_tiles: i32 = config
            .get("hostile_tiles")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);

        self.kernel = Some(TerritoryKernel::new(
            grid_w,
            grid_h,
            packed_byte_to_vec(&claimable),
            packed_f32_to_vec(&elevation),
            packed_f32_to_vec(&flow_mult),
            packed_f32_to_vec(&claim_mult),
            packed_byte_to_vec(&owners),
            packed_f32_to_vec(&pressure_friendly),
            packed_f32_to_vec(&pressure_hostile),
            friendly_spawn_rate,
            hostile_spawn_rate,
            player_home_idx,
            enemy_home_idx,
            spawners_from_dict(&config),
            friendly_tiles,
            hostile_tiles,
            use_active_set,
            use_adaptive_double_pass,
        ));
        true
    }

    #[func]
    fn update_claimable(
        &mut self,
        claimable: PackedByteArray,
        elevation: PackedFloat32Array,
        flow_mult: PackedFloat32Array,
        claim_mult: PackedFloat32Array,
        owners: PackedByteArray,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        kernel.update_claimable(
            packed_byte_to_vec(&claimable),
            packed_f32_to_vec(&elevation),
            packed_f32_to_vec(&flow_mult),
            packed_f32_to_vec(&claim_mult),
            packed_byte_to_vec(&owners),
        );
    }

    #[func]
    fn update_spawners(
        &mut self,
        spawner_teams: PackedByteArray,
        spawner_gx: PackedInt32Array,
        spawner_gy: PackedInt32Array,
    ) {
        let Some(kernel) = self.kernel.as_mut() else {
            return;
        };
        let count = spawner_teams
            .len()
            .min(spawner_gx.len())
            .min(spawner_gy.len());
        kernel.spawners.clear();
        for i in 0..count {
            kernel.spawners.push(Spawner {
                team: spawner_teams.get(i).unwrap_or(0),
                gx: spawner_gx.get(i).unwrap_or(-1),
                gy: spawner_gy.get(i).unwrap_or(-1),
            });
        }
    }

    #[func]
    fn advance_round(&mut self) {
        if let Some(kernel) = self.kernel.as_mut() {
            kernel.advance_round();
        }
    }

    #[func]
    fn advance_rounds(&mut self, n: i32) {
        if let Some(kernel) = self.kernel.as_mut() {
            kernel.advance_rounds(n);
        }
    }

    #[func]
    fn sync_into_tile_control(&self) -> GdDictionary {
        let Some(kernel) = &self.kernel else {
            return GdDictionary::new();
        };
        let mut out = GdDictionary::new();
        let owners = vec_to_packed_byte(&kernel.owners);
        let pressure_friendly = vec_to_packed_f32(&kernel.pressure_friendly);
        let pressure_hostile = vec_to_packed_f32(&kernel.pressure_hostile);
        out.set("owners", &owners);
        out.set("pressure_friendly", &pressure_friendly);
        out.set("pressure_hostile", &pressure_hostile);
        out.set("friendly_tiles", kernel.friendly_tiles);
        out.set("hostile_tiles", kernel.hostile_tiles);
        out
    }

    #[func]
    fn get_owners(&self) -> PackedByteArray {
        match &self.kernel {
            Some(k) => vec_to_packed_byte(&k.owners),
            None => PackedByteArray::new(),
        }
    }

    #[func]
    fn get_pressure_friendly(&self) -> PackedFloat32Array {
        match &self.kernel {
            Some(k) => vec_to_packed_f32(&k.pressure_friendly),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    fn get_pressure_hostile(&self) -> PackedFloat32Array {
        match &self.kernel {
            Some(k) => vec_to_packed_f32(&k.pressure_hostile),
            None => PackedFloat32Array::new(),
        }
    }

    #[func]
    fn get_friendly_tiles(&self) -> i32 {
        self.kernel.as_ref().map(|k| k.friendly_tiles).unwrap_or(0)
    }

    #[func]
    fn get_hostile_tiles(&self) -> i32 {
        self.kernel.as_ref().map(|k| k.hostile_tiles).unwrap_or(0)
    }

    #[func]
    fn encode_pressure_v2(&self, pressure: PackedFloat32Array) -> PackedByteArray {
        vec_to_packed_byte(&encode_pressure_v2(&packed_f32_to_vec(&pressure)))
    }

    #[func]
    fn decode_pressure_v2(&self, blob: PackedByteArray) -> PackedFloat32Array {
        vec_to_packed_f32(&decode_pressure_v2(&packed_byte_to_vec(&blob)))
    }

    #[func]
    fn bake_fluid_rgba(
        &self,
        grid_w: i32,
        grid_h: i32,
        land_mask: PackedByteArray,
        pressure_friendly: PackedFloat32Array,
        pressure_hostile: PackedFloat32Array,
        power_scale: f32,
    ) -> PackedByteArray {
        let bytes = bake_fluid_rgba(
            grid_w,
            grid_h,
            &packed_byte_to_vec(&land_mask),
            &packed_f32_to_vec(&pressure_friendly),
            &packed_f32_to_vec(&pressure_hostile),
            power_scale,
        );
        vec_to_packed_byte(&bytes)
    }

    #[func]
    fn bake_fluid_frames_parallel(
        &self,
        grid_w: i32,
        grid_h: i32,
        land_mask: PackedByteArray,
        frames_friendly: Array<Variant>,
        frames_hostile: Array<Variant>,
        power_scale: f32,
    ) -> Array<Variant> {
        let land = packed_byte_to_vec(&land_mask);
        let n = frames_friendly.len().min(frames_hostile.len());
        let pf_vecs: Vec<Vec<f32>> = (0..n)
            .filter_map(|i| {
                frames_friendly
                    .get(i)
                    .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
                    .map(|a| packed_f32_to_vec(&a))
            })
            .collect();
        let ph_vecs: Vec<Vec<f32>> = (0..n)
            .filter_map(|i| {
                frames_hostile
                    .get(i)
                    .and_then(|v| v.try_to::<PackedFloat32Array>().ok())
                    .map(|a| packed_f32_to_vec(&a))
            })
            .collect();
        let count = pf_vecs.len().min(ph_vecs.len());

        let baked_bytes: Vec<Vec<u8>> = (0..count)
            .into_par_iter()
            .map(|i| {
                bake_fluid_rgba(
                    grid_w,
                    grid_h,
                    &land,
                    &pf_vecs[i],
                    &ph_vecs[i],
                    power_scale,
                )
            })
            .collect();

        let mut out = Array::<Variant>::new();
        for bytes in baked_bytes {
            out.push(&vec_to_packed_byte(&bytes).to_variant());
        }
        out
    }

    #[func]
    fn pack_territory_tape_from_dict(&self, config: GdDictionary) -> PackedByteArray {
        let grid_w: u16 = config.get("grid_w").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let grid_h: u16 = config.get("grid_h").and_then(|v| v.try_to().ok()).unwrap_or(0);
        let record_stride: u16 = config
            .get("record_stride")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(1);
        let frame_count: u32 = config
            .get("frame_count")
            .and_then(|v| v.try_to().ok())
            .unwrap_or(0);
        if frame_count == 0 {
            return PackedByteArray::new();
        }

        let rounds: PackedInt32Array = config
            .get("frame_rounds")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let friendly: PackedInt32Array = config
            .get("frame_friendly")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let hostile: PackedInt32Array = config
            .get("frame_hostile")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let full_flags: PackedByteArray = config
            .get("frame_full_flags")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let owner_blobs: Array<Variant> = config
            .get("frame_owner_blobs")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let delta_blobs: Array<Variant> = config
            .get("frame_delta_blobs")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let pf_blobs: Array<Variant> = config
            .get("frame_pressure_f")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();
        let ph_blobs: Array<Variant> = config
            .get("frame_pressure_h")
            .and_then(|v| v.try_to().ok())
            .unwrap_or_default();

        let fc = frame_count as usize;
        let mut frame_rounds = Vec::with_capacity(fc);
        let mut frame_friendly = Vec::with_capacity(fc);
        let mut frame_hostile = Vec::with_capacity(fc);
        let mut frame_full_flags = Vec::with_capacity(fc);
        let mut frame_owner_full = Vec::with_capacity(fc);
        let mut frame_owner_deltas = Vec::with_capacity(fc);
        let mut frame_pressure_f = Vec::with_capacity(fc);
        let mut frame_pressure_h = Vec::with_capacity(fc);

        for i in 0..fc {
            frame_rounds.push(rounds.get(i).unwrap_or(0) as u32);
            frame_friendly.push(friendly.get(i).unwrap_or(0) as u16);
            frame_hostile.push(hostile.get(i).unwrap_or(0) as u16);
            frame_full_flags.push(full_flags.get(i).unwrap_or(0));

            if frame_full_flags[i] != 0 {
                let blob: PackedByteArray = owner_blobs
                    .get(i)
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                frame_owner_full.push(packed_byte_to_vec(&blob));
                frame_owner_deltas.push(Vec::new());
            } else {
                frame_owner_full.push(Vec::new());
                let delta_blob: PackedByteArray = delta_blobs
                    .get(i)
                    .and_then(|v| v.try_to().ok())
                    .unwrap_or_default();
                let raw = packed_byte_to_vec(&delta_blob);
                let mut deltas = Vec::new();
                let mut j = 0;
                while j + 2 < raw.len() {
                    let idx = u16::from_le_bytes([raw[j], raw[j + 1]]);
                    let owner = raw[j + 2];
                    deltas.push((idx, owner));
                    j += 3;
                }
                frame_owner_deltas.push(deltas);
            }

            let pf: PackedByteArray = pf_blobs
                .get(i)
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            let ph: PackedByteArray = ph_blobs
                .get(i)
                .and_then(|v| v.try_to().ok())
                .unwrap_or_default();
            frame_pressure_f.push(packed_byte_to_vec(&pf));
            frame_pressure_h.push(packed_byte_to_vec(&ph));
        }

        vec_to_packed_byte(&pack_territory_tape_v2(
            grid_w,
            grid_h,
            record_stride,
            frame_count,
            &frame_rounds,
            &frame_friendly,
            &frame_hostile,
            &frame_full_flags,
            &frame_owner_full,
            &frame_owner_deltas,
            &frame_pressure_f,
            &frame_pressure_h,
        ))
    }
}
