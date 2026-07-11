class_name EconomyLib
extends RefCounted

## Compiled economy tables — load once per run; hot paths use numeric arrays only.

const Catalog := preload("res://EconomyCatalog.gd")
const CFG := preload("res://WorldConquestConfig.gd")

class EconomyTables:
	var pack_id: String = ""
	var structure_supply_cost: PackedFloat32Array = PackedFloat32Array()
	var structure_resources: PackedFloat32Array = PackedFloat32Array()
	var structure_build_sec: PackedFloat32Array = PackedFloat32Array()
	var structure_max_health: PackedFloat32Array = PackedFloat32Array()
	var structure_logistics_drain: PackedFloat32Array = PackedFloat32Array()
	var structure_spawn_unit: PackedInt32Array = PackedInt32Array()
	var structure_spawn_interval: PackedFloat32Array = PackedFloat32Array()
	var structure_spawn_max_active: PackedInt32Array = PackedInt32Array()
	var structure_spawn_supply: PackedFloat32Array = PackedFloat32Array()
	var structure_spawn_resources: PackedFloat32Array = PackedFloat32Array()
	var unit_global_cap: PackedInt32Array = PackedInt32Array()
	var unit_upkeep_supply: PackedFloat32Array = PackedFloat32Array()
	var unit_upkeep_resources: PackedFloat32Array = PackedFloat32Array()
	var hud_structure_labels: Dictionary = {}
	var kind_to_u8: Dictionary = {}


static var _tables: EconomyTables = null
static var _loaded_pack_id: String = ""


static func is_loaded() -> bool:
	return _tables != null


static func tables() -> EconomyTables:
	return _tables


static func ensure_loaded(pack_id: String = Catalog.PACK_DEFAULT) -> void:
	var resolved: String = Catalog.resolve_pack_id(pack_id)
	if _tables != null and _loaded_pack_id == resolved:
		return
	_tables = _compile(Catalog.get_pack(resolved))
	_loaded_pack_id = resolved


static func reset() -> void:
	_tables = null
	_loaded_pack_id = ""


static func kind_index(kind: String) -> int:
	ensure_loaded()
	return Catalog.kind_u8(kind)


static func placement_cost(kind: String) -> Vector4:
	## x=supply, yzw=unused; use placement_cost_vectors for full cost.
	ensure_loaded()
	var idx: int = Catalog.kind_u8(kind)
	if idx < 0:
		return Vector4.ZERO
	return Vector4(
		_tables.structure_supply_cost[idx],
		_tables.structure_resources[idx * Catalog.RESOURCE_SLOTS + 0],
		_tables.structure_resources[idx * Catalog.RESOURCE_SLOTS + 1],
		_tables.structure_resources[idx * Catalog.RESOURCE_SLOTS + 2],
	)


static func supply_cost(kind: String) -> float:
	return placement_cost(kind).x


static func build_sec_for_kind(kind: String) -> float:
	ensure_loaded()
	var idx: int = Catalog.kind_u8(kind)
	if idx < 0:
		return CFG.OUTPOST_BUILD_SEC
	return _tables.structure_build_sec[idx]


static func structure_spawn_cost_resources(kind: String) -> PackedFloat32Array:
	ensure_loaded()
	var idx: int = Catalog.kind_u8(kind)
	if idx < 0:
		return PackedFloat32Array([0.0, 0.0, 0.0])
	var base: int = idx * Catalog.RESOURCE_SLOTS
	return PackedFloat32Array([
		_tables.structure_spawn_resources[base],
		_tables.structure_spawn_resources[base + 1],
		_tables.structure_spawn_resources[base + 2],
	])


static func soldier_spawn_aurelium_cost() -> float:
	ensure_loaded()
	return _tables.structure_spawn_resources[
		Catalog.kind_u8(Catalog.KIND_BARRACKS) * Catalog.RESOURCE_SLOTS
	]


static func bomber_spawn_aurelium_cost() -> float:
	ensure_loaded()
	return _tables.structure_spawn_resources[
		Catalog.kind_u8(Catalog.KIND_HANGAR) * Catalog.RESOURCE_SLOTS
	]


static func soldier_upkeep_aurelium_per_sec() -> float:
	ensure_loaded()
	var unit_idx: int = Catalog.unit_u8(Catalog.UNIT_SOLDIER)
	return _tables.unit_upkeep_resources[unit_idx * Catalog.RESOURCE_SLOTS]


static func can_afford_build(supply: float, resources: Array, kind: String) -> bool:
	var cost: Vector4 = placement_cost(kind)
	if supply < cost.x:
		return false
	if resources.size() < Catalog.RESOURCE_SLOTS:
		return cost.y <= 0.0 and cost.z <= 0.0 and cost.w <= 0.0
	return (
		float(resources[0]) >= cost.y
		and float(resources[1]) >= cost.z
		and float(resources[2]) >= cost.w
	)


static func pay_build(supply: float, resources: Array, kind: String) -> Dictionary:
	var cost: Vector4 = placement_cost(kind)
	var out_supply: float = supply - cost.x
	var out_resources: Array[float] = [0.0, 0.0, 0.0]
	for i in Catalog.RESOURCE_SLOTS:
		var have: float = float(resources[i]) if i < resources.size() else 0.0
		var slot_cost: float = cost[1 + i]
		out_resources[i] = have - slot_cost
	return {"supply": out_supply, "resources": out_resources}


static func hud_label_for_kind(kind: String) -> String:
	ensure_loaded()
	return str(_tables.hud_structure_labels.get(kind, kind))


static func export_rust_bundle() -> Dictionary:
	ensure_loaded()
	return {
		"structure_build_sec": _tables.structure_build_sec,
		"structure_max_health": _tables.structure_max_health,
		"structure_logistics_drain": _tables.structure_logistics_drain,
		"structure_spawn_interval": _tables.structure_spawn_interval,
		"structure_spawn_max_active": _tables.structure_spawn_max_active,
		"structure_spawn_unit": _tables.structure_spawn_unit,
		"structure_spawn_resources": _tables.structure_spawn_resources,
		"unit_global_cap": _tables.unit_global_cap,
		"unit_upkeep_resources": _tables.unit_upkeep_resources,
		"soldier_spawn_cost": soldier_spawn_aurelium_cost(),
		"bomber_spawn_cost": bomber_spawn_aurelium_cost(),
		"outpost_enemy_dps": CFG.OUTPOST_ENEMY_DPS,
		"soldier_upkeep_deficit_dps": CFG.SOLDIER_UPKEEP_DEFICIT_DPS,
		"road_cells_per_sec": CFG.OUTPOST_ROAD_CELLS_PER_SEC,
		"reconcile_cells_per_frame": CFG.LOGISTICS_RECONCILE_CELLS_PER_FRAME,
		"full_recal_interval_sec": CFG.LOGISTICS_FULL_RECAL_SEC,
		"placement_heat_decay_per_sec": CFG.LOGISTICS_PLACEMENT_HEAT_DECAY,
		"burst_base": CFG.LOGISTICS_BURST_BASE,
		"burst_ratio": CFG.LOGISTICS_BURST_RATIO,
		"strain_sensitivity": CFG.LOGISTICS_STRAIN_SENSITIVITY,
	}


static func validate_parity() -> Dictionary:
	ensure_loaded(Catalog.PACK_DEFAULT)
	var issues: PackedStringArray = PackedStringArray()
	for kind: String in Catalog.structure_kind_ids():
		if Catalog.kind_u8(kind) < 0:
			issues.append("missing kind_u8 for %s" % kind)
		var idx: int = Catalog.kind_u8(kind)
		var expected_supply: float = 0.0
		match kind:
			Catalog.KIND_SPAWNER:
				expected_supply = CFG.SPAWNER_COST_SUPPLY
			Catalog.KIND_BARRACKS:
				expected_supply = CFG.BARRACKS_COST_SUPPLY
			Catalog.KIND_CORRIDOR_LINK:
				expected_supply = CFG.CORRIDOR_LINK_COST_SUPPLY
			Catalog.KIND_HANGAR:
				expected_supply = CFG.HANGAR_COST_SUPPLY
		if absf(_tables.structure_supply_cost[idx] - expected_supply) > 0.001:
			issues.append(
				"supply mismatch %s baked=%.2f cfg=%.2f"
				% [kind, _tables.structure_supply_cost[idx], expected_supply]
			)
	if absf(soldier_spawn_aurelium_cost() - CFG.SOLDIER_SPAWN_AURELIUM_COST) > 0.001:
		issues.append("soldier spawn cost mismatch")
	if absf(bomber_spawn_aurelium_cost() - CFG.BOMBER_SPAWN_AURELIUM_COST) > 0.001:
		issues.append("bomber spawn cost mismatch")
	if absf(soldier_upkeep_aurelium_per_sec() - CFG.SOLDIER_UPKEEP_AURELIUM_PER_SEC) > 0.001:
		issues.append("soldier upkeep mismatch")
	return {"ok": issues.is_empty(), "issues": issues}


static func _compile(pack: Dictionary) -> EconomyTables:
	var t := EconomyTables.new()
	t.pack_id = str(pack.get("pack_id", Catalog.PACK_DEFAULT))
	var structures: Dictionary = pack.get("structures", {})
	var units: Dictionary = pack.get("units", {})

	t.structure_supply_cost.resize(Catalog.MAX_KINDS)
	t.structure_resources.resize(Catalog.MAX_KINDS * Catalog.RESOURCE_SLOTS)
	t.structure_build_sec.resize(Catalog.MAX_KINDS)
	t.structure_max_health.resize(Catalog.MAX_KINDS)
	t.structure_logistics_drain.resize(Catalog.MAX_KINDS)
	t.structure_spawn_unit.resize(Catalog.MAX_KINDS)
	t.structure_spawn_interval.resize(Catalog.MAX_KINDS)
	t.structure_spawn_max_active.resize(Catalog.MAX_KINDS)
	t.structure_spawn_supply.resize(Catalog.MAX_KINDS)
	t.structure_spawn_resources.resize(Catalog.MAX_KINDS * Catalog.RESOURCE_SLOTS)

	for kind: String in Catalog.structure_kind_ids():
		var idx: int = Catalog.kind_u8(kind)
		t.kind_to_u8[kind] = idx
		var def: Dictionary = structures.get(kind, {})
		var cost: Dictionary = def.get("cost", {})
		var res: Array = cost.get("resources", [0.0, 0.0, 0.0])
		t.structure_supply_cost[idx] = float(cost.get("supply", 0.0))
		for r in Catalog.RESOURCE_SLOTS:
			t.structure_resources[idx * Catalog.RESOURCE_SLOTS + r] = (
				float(res[r]) if r < res.size() else 0.0
			)
		t.structure_build_sec[idx] = float(def.get("build_sec", 0.0))
		t.structure_max_health[idx] = float(def.get("max_health", CFG.OUTPOST_MAX_HEALTH))
		t.structure_logistics_drain[idx] = float(def.get("logistics_drain", 0.0))
		var spawns: Dictionary = def.get("spawns", {})
		if spawns.is_empty():
			t.structure_spawn_unit[idx] = -1
			t.structure_spawn_interval[idx] = 0.0
			t.structure_spawn_max_active[idx] = 0
		else:
			var unit_id: String = str(spawns.get("unit_id", ""))
			t.structure_spawn_unit[idx] = Catalog.unit_u8(unit_id)
			t.structure_spawn_interval[idx] = float(spawns.get("interval_sec", 0.0))
			t.structure_spawn_max_active[idx] = int(spawns.get("max_active", 0))
			var spawn_cost: Dictionary = spawns.get("spawn_cost", {})
			t.structure_spawn_supply[idx] = float(spawn_cost.get("supply", 0.0))
			var spawn_res: Array = spawn_cost.get("resources", [0.0, 0.0, 0.0])
			for r in Catalog.RESOURCE_SLOTS:
				t.structure_spawn_resources[idx * Catalog.RESOURCE_SLOTS + r] = (
					float(spawn_res[r]) if r < spawn_res.size() else 0.0
				)
		var display: String = str(def.get("display_name", kind))
		t.hud_structure_labels[kind] = "%s (%d)" % [display, int(t.structure_supply_cost[idx])]

	t.unit_global_cap.resize(Catalog.MAX_UNITS)
	t.unit_upkeep_supply.resize(Catalog.MAX_UNITS)
	t.unit_upkeep_resources.resize(Catalog.MAX_UNITS * Catalog.RESOURCE_SLOTS)
	for unit_id: String in Catalog.unit_ids():
		var uidx: int = Catalog.unit_u8(unit_id)
		var udef: Dictionary = units.get(unit_id, {})
		t.unit_global_cap[uidx] = int(udef.get("global_cap", 0))
		var upkeep: Dictionary = udef.get("upkeep_per_sec", {})
		t.unit_upkeep_supply[uidx] = float(upkeep.get("supply", 0.0))
		var upkeep_res: Array = upkeep.get("resources", [0.0, 0.0, 0.0])
		for r in Catalog.RESOURCE_SLOTS:
			t.unit_upkeep_resources[uidx * Catalog.RESOURCE_SLOTS + r] = (
				float(upkeep_res[r]) if r < upkeep_res.size() else 0.0
			)
	return t
