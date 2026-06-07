class_name WorldRTS3DConfig
extends RefCounted

## Compact 3D prototype map (~7× fewer tiles than 2D world).
const GRID_W := 56
const GRID_H := 42
const CELL_SIZE := 3.0
const HEIGHT_SCALE := 14.0
## Lift fluid surface above terrain verts so it is not buried under hills.
const FLUID_SURFACE_LIFT := 1.35

const PLAYER_FORCE := 200
const ENEMY_FORCE := 200

const SPAWNER_COST_POWER := 500_000
const STARTING_WALLET_POWER := 1_250_000
const INCOME_PER_OWNED_TILE_PER_SEC := 55.0
const MIN_SPAWNER_SPACING_CELLS := 8

const SIM_ROUNDS_PER_SEC := 14.0
const SIM_MAX_ROUNDS_PER_FRAME := 12
const OVERLAY_UPDATES_PER_SEC := 10.0
const SIM_ACTIVE_SOFT_CAP := 2200

const CAMERA_PAN_SPEED := 38.0
const CAMERA_ZOOM_STEP := 1.1
const CAMERA_MIN_HEIGHT := 18.0
const CAMERA_MAX_HEIGHT := 120.0
const CAMERA_DEFAULT_HEIGHT := 52.0
