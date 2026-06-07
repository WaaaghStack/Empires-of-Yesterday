class_name WorldRTSConfig
extends RefCounted

## Grid: 192×144 ≈ 28k tiles (world prototype; was 288×216).
const GRID_W := 192
const GRID_H := 144
const CELL_SIZE := 16.0

const PLAYER_FORCE := 500
const ENEMY_FORCE := 500

const SPAWNER_BUILDING_ID := "world_spawner"
const SPAWNER_COST_POWER := 1_000_000
const STARTING_WALLET_POWER := 2_500_000
## Strategic power income (not fluid pressure on the map).
const INCOME_PER_OWNED_TILE_PER_SEC := 40.0
const MIN_SPAWNER_SPACING_CELLS := 10

const SIM_ROUNDS_PER_SEC := 10.0
const SIM_MAX_ROUNDS_PER_FRAME := 8
const OVERLAY_UPDATES_PER_SEC := 5.0
## Above this active frontier size, cap sim rounds further (keeps late battle smooth).
const SIM_ACTIVE_SOFT_CAP := 4500

const CAMERA_PAN_SPEED := 520.0
const CAMERA_ZOOM_STEP := 1.12
const CAMERA_FIT_MARGIN := 0.94
