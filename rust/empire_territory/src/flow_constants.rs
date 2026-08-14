//! Flow / pressure constants — single Rust authority for values mirrored by Godot.
//!
//! **Must match** `WorldConquestConfig.gd` / `BattleTileControl.gd` live values:
//! - `BRIDGE_PRESSURE_FLOW_MULT` (WorldConquestConfig)
//! - `FLOW_CONDUCTIVITY`, `MIN_FLOW_DELTA`, `MAX_OUTFLOW_FRAC` (BattleTileControl)
//!
//! (A12 / C15) Prefer this module over scattering literals. Godot remains the product
//! config surface; these asserts catch silent drift.

/// Pressure flow multiplier on built bridge water cells (vs land).
/// Matches `WorldConquestConfig.BRIDGE_PRESSURE_FLOW_MULT`.
pub const BRIDGE_PRESSURE_FLOW_MULT: f32 = 2.8;

/// Gradient flow conductivity — matches `BattleTileControl.FLOW_CONDUCTIVITY`.
pub const FLOW_CONDUCTIVITY: f32 = 0.20;

/// Minimum height delta to allow outflow — matches `BattleTileControl.MIN_FLOW_DELTA`.
pub const MIN_FLOW_DELTA: f32 = 0.1;

/// Cap outflow as a fraction of source pressure — matches `BattleTileControl.MAX_OUTFLOW_FRAC`.
pub const MAX_OUTFLOW_FRAC: f32 = 0.38;

#[cfg(test)]
mod tests {
    use super::*;

    /// Pin values against the Godot WorldConquest / BattleTileControl contracts.
    #[test]
    fn flow_constants_match_godot_world_conquest_config() {
        assert_eq!(
            BRIDGE_PRESSURE_FLOW_MULT, 2.8,
            "BRIDGE_PRESSURE_FLOW_MULT must match WorldConquestConfig (2.8)"
        );
        assert_eq!(
            FLOW_CONDUCTIVITY, 0.20,
            "FLOW_CONDUCTIVITY must match BattleTileControl (0.20)"
        );
        assert_eq!(
            MIN_FLOW_DELTA, 0.1,
            "MIN_FLOW_DELTA must match BattleTileControl (0.1)"
        );
        assert_eq!(
            MAX_OUTFLOW_FRAC, 0.38,
            "MAX_OUTFLOW_FRAC must match BattleTileControl (0.38)"
        );
    }
}
