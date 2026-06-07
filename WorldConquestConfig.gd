class_name WorldConquestConfig
extends RefCounted

## World Conquest — 360×180 equirect Earth globe, human-scale Supply economy.

const GRID_W := 360
const GRID_H := 180
const CELL_SIZE := 1.0

const PLAYER_FORCE := 200
const ENEMY_FORCE := 200

const STARTING_SUPPLY := 1200
const SPAWNER_COST_SUPPLY := 400
const INCOME_PER_TILE_PER_SEC := 0.8

## Discrete sim step (~14/sec); internal only — UI shows sim time.
const SIM_DT := 1.0 / 14.0
const SIM_MAX_STEPS_PER_FRAME := 12
const OVERLAY_UPDATES_PER_SEC := 10.0
const SIM_ACTIVE_SOFT_CAP := 8000

const GLOBE_RADIUS := 100.0
## Subtle displacement so land reads as one continuous shell (not floating plates).
const HEIGHT_SCALE := 7.0
const FLUID_SURFACE_LIFT := 1.6
## Globe render mesh (coarser than sim grid for GPU budget).
const GLOBE_MESH_W := 144
const GLOBE_MESH_H := 72
## Finer mesh for the fluid drape so conquest fronts read clearly on the globe.
const FLUID_MESH_W := 180
const FLUID_MESH_H := 90

const MIN_SPAWNER_SPACING_CELLS := 6

## Win / loss thresholds (world conquest context).
const CONQUEST_LAND_FRAC := 0.70
const DOMINANCE_HOLD_SEC := 30.0
const STALL_SEC := 45.0
const DECISIVE_HOLD_SEC := 12.0
const MAX_SIM_TIME_SEC := 3600.0

const CAMERA_ORBIT_SPEED := 0.35
const CAMERA_ZOOM_STEP := 1.12
## Keep camera outside globe radius + max elevation + fluid lift.
const CAMERA_MIN_DISTANCE := 155.0
const CAMERA_MAX_DISTANCE := 320.0
const CAMERA_DEFAULT_DISTANCE := 200.0

## Slower creep spread than compact RTS maps (HOME_START_POWER / 2000 per step).
const WORLD_CONQUEST_PRESSURE_SCALE := 1.0 / 2000.0
