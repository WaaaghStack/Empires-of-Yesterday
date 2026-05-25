class_name MissionMapData
extends RefCounted

const PathGraphScript := preload("res://DynamicPathGraph.gd")

var map_seed: int = 0
var map_size: Vector2 = Vector2(1024, 640)
var rooms: Array[Dictionary] = []
var corridors: Array[Rect2] = []
var hull_outline: PackedVector2Array = PackedVector2Array()
var path_graph = PathGraphScript.new()
var objective_template: String = "standard"
var op_index: int = 1
var enemy_stat_scale: float = 1.0
var evac_reveal_after_searches: int = 0
var bonus_credits_room_id: String = ""
var hold_room_id: String = ""
var hold_duration_seconds: float = 0.0
var intel_terminal_room_ids: Array[String] = []
var vip_room_id: String = ""
var loot_branch_room_id: String = ""
var facility_theme: String = "industrial"
var is_handcrafted: bool = false
var map_tier: String = "medium"
var map_scale: float = 1.0
var hive_room_ids: Array[String] = []
var overmind_room_id: String = ""
var sector_tags: Dictionary = {}
## Mass-unit scale (500–10k). Off by default — campaign unchanged.
var mass_unit_mode: bool = false
var max_units: int = 10000
var full_tier_cap: int = 300
var initial_friendlies: int = 0
var initial_hostiles: int = 0
var active_lite_cap: int = 2000
var dormant_reserve: int = 8000
var battle_map_preset: bool = false

func get_room_dicts() -> Array[Dictionary]:
	return rooms

func get_corridor_rects() -> Array[Rect2]:
	return corridors

func get_hull_outline() -> PackedVector2Array:
	return hull_outline
