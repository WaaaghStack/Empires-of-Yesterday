extends Node3D

const CFG := preload("res://WorldConquestConfig.gd")
const MapGen := preload("res://WorldConquestMapGenerator.gd")

const _PREVIEW_SHADER: Shader = preload("res://shaders/globe/menu_preview.gdshader")
const _ATMO_SHADER: Shader = preload("res://shaders/globe/atmosphere_rim.gdshader")
const _LAND_MASK: Texture2D = preload("res://data/earth/land_mask_360x180.png")

var _globe_mi: MeshInstance3D
var _mat: ShaderMaterial
var _spin: float = 0.12
var _yaw: float = -0.6


func _ready() -> void:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 72
	sm.rings = 40
	_globe_mi = MeshInstance3D.new()
	_globe_mi.mesh = sm
	_mat = ShaderMaterial.new()
	_mat.shader = _PREVIEW_SHADER
	_mat.set_shader_parameter("land_mask", _LAND_MASK)
	_globe_mi.material_override = _mat
	add_child(_globe_mi)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.55
	env_node.environment = env
	add_child(env_node)
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 1.045
	am.height = 2.09
	am.radial_segments = 48
	am.rings = 24
	atmo.mesh = am
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var amat := ShaderMaterial.new()
	amat.shader = _ATMO_SHADER
	amat.set_shader_parameter("atmosphere_color", Vector3(0.35, 0.55, 0.85))
	amat.set_shader_parameter("intensity", 0.45)
	amat.set_shader_parameter("power", 2.4)
	atmo.material_override = amat
	add_child(atmo)
	apply_theater(CFG.THEATER_EARTH, 0.0, 0.0, 1.0)


func _process(delta: float) -> void:
	_yaw += _spin * delta
	_globe_mi.rotation.y = _yaw


func apply_theater(theater_id: String, land_bias: float, mountain_bias: float, resource_density: float) -> void:
	if _mat == null:
		return
	var mode: float = 0.0
	match CFG.normalize_theater_id(theater_id):
		CFG.THEATER_PANGEA:
			mode = 1.0
		CFG.THEATER_ARCHIPELAGO:
			mode = 2.0
		_:
			mode = 0.0
	var pal: Dictionary = MapGen.globe_colors_for_map("earth")
	var ocean: Color = pal.get("ocean", Color(0.05, 0.18, 0.42))
	var land: Color = pal.get("land", Color(0.34, 0.52, 0.28))
	var mountain: Color = pal.get("mountain", Color(0.48, 0.44, 0.38))
	var sand: Color = pal.get("sand", Color(0.72, 0.64, 0.38))
	_mat.set_shader_parameter("theater_mode", mode)
	_mat.set_shader_parameter("land_bias", land_bias)
	_mat.set_shader_parameter("mountain_bias", mountain_bias)
	_mat.set_shader_parameter("resource_density", resource_density)
	_mat.set_shader_parameter("ocean_col", Vector3(ocean.r, ocean.g, ocean.b))
	_mat.set_shader_parameter("land_col", Vector3(land.r, land.g, land.b))
	_mat.set_shader_parameter("mountain_col", Vector3(mountain.r, mountain.g, mountain.b))
	_mat.set_shader_parameter("sand_col", Vector3(sand.r, sand.g, sand.b))


func set_meridian_highlight(mode: int) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("meridian_mode", float(clampi(mode, 0, 2)))
