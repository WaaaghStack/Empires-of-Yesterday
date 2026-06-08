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
## Outpost must link by road from HQ or nearest active outpost, then finish construction.
const OUTPOST_BUILD_SEC := 5.0
const OUTPOST_ROAD_CELLS_PER_SEC := 1.0
## Bridge deck height above globe sea level (water tiles).
const BRIDGE_SURFACE_LIFT := 3.4
## Safety cap for route search (bidirectional); avoids multi-second ocean floods.
const OUTPOST_PATHFIND_MAX_EXPAND := 12000
const OUTPOST_MAX_HEALTH := 10.0
const OUTPOST_ENEMY_DPS := 3.0

## Win: all claimable land, or enemy cumulative power reaches zero.
const CONQUEST_LAND_FRAC := 1.0
const MAX_SIM_TIME_SEC := 7200.0
## Hostile pressure total at or below this counts as zero (matches HUD integer display).
const ZERO_POWER_VICTORY_EPS := 0.5

const CAMERA_ORBIT_SPEED := 0.35
const CAMERA_PITCH_MIN := -1.2
const CAMERA_PITCH_MAX := 1.2
const CAMERA_ZOOM_STEP := 1.12
## Keep camera outside globe radius + max elevation + fluid lift.
const CAMERA_MIN_DISTANCE := 155.0
const CAMERA_MAX_DISTANCE := 320.0
const CAMERA_DEFAULT_DISTANCE := 200.0

## Slower creep spread than compact RTS maps (HOME_START_POWER / 2000 per step).
const WORLD_CONQUEST_PRESSURE_SCALE := 1.0 / 2000.0

## Strategic minerals — Aurelium (yellow), Verdantite (green), Emberstone (orange).
const RESOURCE_TYPE_COUNT := 3
const RESOURCE_NAMES: Array[String] = ["Aurelium", "Verdantite", "Emberstone"]
const RESOURCE_SHORT: Array[String] = ["Au", "Ve", "Em"]
const RESOURCE_COLORS: Array[Color] = [
	Color(0.98, 0.86, 0.22, 1.0),
	Color(0.28, 0.88, 0.42, 1.0),
	Color(0.98, 0.52, 0.18, 1.0),
]
const RESOURCE_BLOBS_PER_TYPE := 22
const RESOURCE_BLOB_MIN_SPACING := 10
const RESOURCE_SPAWN_EXCLUSION := 24
## Yield per second by blob size tier (1 small, 2 medium, 3 large).
const RESOURCE_YIELD_BY_SIZE: Array[float] = [0.0, 0.6, 1.0, 1.8]
const RESOURCE_BLOB_CELL_COUNT: Array[int] = [0, 4, 9, 18]
const RESOURCE_LINK_CELLS_PER_SEC := 1.2
const RESOURCE_HAUL_CELLS_PER_SEC := 2.5
## Cap simultaneous haul pulse draw instances (economy still credits all yields).
const RESOURCE_MAX_VISUAL_PULSES := 36
