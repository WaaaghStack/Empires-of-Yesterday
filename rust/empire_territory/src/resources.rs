//! Team resource balances (Phase 8 — side table; deposit tick still in GDScript).

#[derive(Clone, Debug, Default)]
pub struct ResourceWallet {
    pub friendly: [f32; 3],
    pub hostile: [f32; 3],
}

impl ResourceWallet {
    pub fn apply_delta(&mut self, friendly: &[f32; 3], hostile: &[f32; 3]) {
        for i in 0..3 {
            self.friendly[i] += friendly[i];
            self.hostile[i] += hostile[i];
        }
    }

    pub fn add_friendly_supply_income(&mut self, tiles: i32, income_per_tile: f32, dt: f32) {
        if tiles > 0 && dt > 0.0 && income_per_tile > 0.0 {
            self.friendly[0] += tiles as f32 * income_per_tile * dt;
        }
    }

    pub fn add_hostile_supply_income(&mut self, tiles: i32, income_per_tile: f32, dt: f32) {
        if tiles > 0 && dt > 0.0 && income_per_tile > 0.0 {
            self.hostile[0] += tiles as f32 * income_per_tile * dt;
        }
    }
}
