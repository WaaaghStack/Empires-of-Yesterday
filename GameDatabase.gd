# GameDatabase.gd — SQLite persistence via godot-sqlite (no C# / .NET).
extends Node

const DB_PATH := "user://game.db"
const PROFILE_JSON_PATH := "user://profile.save"
const SCHEMA_VERSION := 8

const BattleReplayPackLib := preload("res://BattleReplayPack.gd")

const BattleSqlPersistLib := preload("res://BattleSqlPersist.gd")
const BattleMapSnapshotLib := preload("res://BattleMapSnapshot.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const SimpleFluidSimulator := preload("res://SimpleFluidSimulator.gd")

var _db: Object = null


func _ready() -> void:
	_open_db()
	_migrate()
	_import_legacy_profile_if_needed()
	print("[GameDatabase] Opened ", DB_PATH)


func _exit_tree() -> void:
	_close_db()


func _open_db() -> void:
	_close_db()
	_db = ClassDB.instantiate("SQLite")
	if _db == null:
		push_error("[GameDatabase] godot-sqlite not loaded — enable Project Settings → Plugins → Godot SQLite")
		return
	_db.path = DB_PATH
	if not _db.open_db():
		push_error("[GameDatabase] open failed: ", _db.error_message)


func _close_db() -> void:
	if _db != null and _db.has_method("close_db"):
		_db.close_db()
	_db = null


func _ensure_db() -> bool:
	if _db == null:
		push_error("[GameDatabase] Database not open")
		return false
	return true


func _execute(sql: String, args: Array = []) -> bool:
	if not _ensure_db():
		return false
	if not _db.query_with_bindings(sql, args):
		push_error("[GameDatabase] SQL error: ", _db.error_message)
		return false
	return true


func _query(sql: String, args: Array = []) -> Array:
	if not _ensure_db():
		return []
	if not _db.query_with_bindings(sql, args):
		push_error("[GameDatabase] SQL error: ", _db.error_message)
		return []
	var out: Array = []
	for row in _db.query_result:
		if typeof(row) == TYPE_DICTIONARY:
			out.append(row)
	return out


func _last_insert_id() -> int:
	var rows := _query("SELECT last_insert_rowid() AS id")
	if rows.is_empty():
		return 0
	return int(rows[0].get("id", 0))


# --- Schema ---

func _migrate() -> void:
	_execute(
		"CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL PRIMARY KEY);"
	)
	var rows := _query("SELECT version FROM schema_version LIMIT 1")
	var version: int = int(rows[0].get("version", 0)) if not rows.is_empty() else 0
	if version < 1:
		_apply_schema_v1()
	if version < 2:
		_apply_schema_v2()
	if version < 3:
		_apply_schema_v3()
	if version < 4:
		_apply_schema_v4()
	if version < 5:
		_apply_schema_v5()
	if version < 6:
		_apply_schema_v6()
	if version < 7:
		_apply_schema_v7()
	if version < 8:
		_apply_schema_v8()
	if version < SCHEMA_VERSION:
		_execute("DELETE FROM schema_version")
		_execute("INSERT INTO schema_version (version) VALUES (?)", [SCHEMA_VERSION])


func _apply_schema_v1() -> void:
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS profile (
			id INTEGER PRIMARY KEY CHECK (id = 1),
			command_tokens INTEGER NOT NULL DEFAULT 0,
			carrier_biomass INTEGER NOT NULL DEFAULT 0,
			total_runs INTEGER NOT NULL DEFAULT 0,
			total_ops_cleared INTEGER NOT NULL DEFAULT 0,
			best_run_depth INTEGER NOT NULL DEFAULT 0,
			unlocked_classes TEXT NOT NULL DEFAULT '[0,1]',
			unlocked_portraits TEXT NOT NULL DEFAULT '[]',
			discovered_modifiers TEXT NOT NULL DEFAULT '[]',
			discovered_enemies TEXT NOT NULL DEFAULT '[]',
			discovered_objectives TEXT NOT NULL DEFAULT '[]',
			daily_best_date TEXT NOT NULL DEFAULT '',
			daily_best_ops INTEGER NOT NULL DEFAULT 0,
			daily_best_kia INTEGER NOT NULL DEFAULT 999,
			daily_best_time REAL NOT NULL DEFAULT 999999,
			ascension_level INTEGER NOT NULL DEFAULT 0,
			codex_achievements TEXT NOT NULL DEFAULT '[]'
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS commander_runs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			commander_id TEXT NOT NULL,
			run_seed INTEGER NOT NULL,
			run_credits INTEGER NOT NULL DEFAULT 0,
			turn_index INTEGER NOT NULL DEFAULT 0,
			is_active INTEGER NOT NULL DEFAULT 1,
			pending_battle_node_id TEXT NOT NULL DEFAULT '',
			created_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS run_snapshots (
			run_id INTEGER PRIMARY KEY,
			galaxy_json TEXT NOT NULL,
			army_json TEXT NOT NULL,
			resources_json TEXT NOT NULL,
			FOREIGN KEY (run_id) REFERENCES commander_runs(id) ON DELETE CASCADE
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battles (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			run_id INTEGER NOT NULL,
			node_id TEXT NOT NULL,
			terrain_tag TEXT NOT NULL DEFAULT 'open_field',
			player_force INTEGER NOT NULL,
			enemy_force INTEGER NOT NULL,
			map_seed INTEGER NOT NULL,
			player_won INTEGER NOT NULL DEFAULT 0,
			player_losses INTEGER NOT NULL DEFAULT 0,
			enemy_losses INTEGER NOT NULL DEFAULT 0,
			turns INTEGER NOT NULL DEFAULT 0,
			resolve_ms REAL NOT NULL DEFAULT 0,
			resolve_mode TEXT NOT NULL DEFAULT 'tactical',
			replay_json TEXT NOT NULL DEFAULT '',
			FOREIGN KEY (run_id) REFERENCES commander_runs(id) ON DELETE CASCADE
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_queue (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			run_id INTEGER NOT NULL,
			battle_id INTEGER NOT NULL,
			queue_order INTEGER NOT NULL,
			resolved INTEGER NOT NULL DEFAULT 0,
			label TEXT NOT NULL DEFAULT '',
			FOREIGN KEY (run_id) REFERENCES commander_runs(id) ON DELETE CASCADE,
			FOREIGN KEY (battle_id) REFERENCES battles(id) ON DELETE CASCADE
		);
		"""
	)
	_execute("CREATE INDEX IF NOT EXISTS idx_battles_run ON battles(run_id);")
	_execute("CREATE INDEX IF NOT EXISTS idx_queue_run ON battle_queue(run_id, resolved);")


func _apply_schema_v2() -> void:
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_maps (
			battle_id INTEGER PRIMARY KEY,
			grid_width INTEGER NOT NULL,
			grid_height INTEGER NOT NULL,
			cell_size REAL NOT NULL,
			contact_column INTEGER NOT NULL,
			map_seed INTEGER NOT NULL,
			terrain_tag TEXT NOT NULL,
			map_json TEXT NOT NULL,
			FOREIGN KEY (battle_id) REFERENCES battles(id) ON DELETE CASCADE
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_tiles (
			battle_id INTEGER NOT NULL,
			tile_id INTEGER NOT NULL,
			gx INTEGER NOT NULL,
			gy INTEGER NOT NULL,
			terrain INTEGER NOT NULL,
			blocked INTEGER NOT NULL DEFAULT 0,
			cover INTEGER NOT NULL DEFAULT 0,
			move_cost REAL NOT NULL DEFAULT 1.0,
			defense REAL NOT NULL DEFAULT 1.0,
			PRIMARY KEY (battle_id, tile_id)
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_units (
			battle_id INTEGER NOT NULL,
			unit_index INTEGER NOT NULL,
			side INTEGER NOT NULL,
			archetype INTEGER NOT NULL DEFAULT 0,
			max_hp REAL NOT NULL DEFAULT 1.0,
			unit_size INTEGER NOT NULL DEFAULT 1,
			PRIMARY KEY (battle_id, unit_index)
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_rounds (
			battle_id INTEGER NOT NULL,
			frame_index INTEGER NOT NULL,
			round_index INTEGER NOT NULL,
			friendly_living INTEGER NOT NULL DEFAULT 0,
			hostile_living INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (battle_id, frame_index)
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_unit_state (
			battle_id INTEGER NOT NULL,
			frame_index INTEGER NOT NULL,
			unit_index INTEGER NOT NULL,
			tile_id INTEGER NOT NULL,
			gx INTEGER NOT NULL,
			gy INTEGER NOT NULL,
			hp REAL NOT NULL,
			alive INTEGER NOT NULL,
			routed INTEGER NOT NULL DEFAULT 0,
			tier INTEGER NOT NULL DEFAULT 0,
			flags INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (battle_id, frame_index, unit_index)
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_unit_moves (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			battle_id INTEGER NOT NULL,
			frame_index INTEGER NOT NULL,
			round_index INTEGER NOT NULL,
			unit_index INTEGER NOT NULL,
			from_tile_id INTEGER NOT NULL,
			to_tile_id INTEGER NOT NULL
		);
		"""
	)
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_meta (
			battle_id INTEGER PRIMARY KEY,
			frame_count INTEGER NOT NULL,
			record_stride INTEGER NOT NULL DEFAULT 1,
			round_duration REAL NOT NULL DEFAULT 0.42,
			resolve_ms REAL NOT NULL DEFAULT 0
		);
		"""
	)
	_execute(
		"CREATE INDEX IF NOT EXISTS idx_battle_unit_state_frame ON battle_unit_state (battle_id, frame_index);"
	)
	_execute(
		"CREATE INDEX IF NOT EXISTS idx_battle_unit_moves_battle ON battle_unit_moves (battle_id, frame_index);"
	)


func _apply_schema_v3() -> void:
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_tile_frames (
			battle_id INTEGER NOT NULL,
			frame_index INTEGER NOT NULL,
			owners BLOB NOT NULL,
			PRIMARY KEY (battle_id, frame_index)
		);
		"""
	)
	_execute(
		"CREATE INDEX IF NOT EXISTS idx_battle_tile_frames ON battle_tile_frames (battle_id, frame_index);"
	)


func _apply_schema_v4() -> void:
	## Schema v4: territory battles persist tile frames only (no unit tables required).
	pass


func _apply_schema_v5() -> void:
	## Schema v5: Revolutionary "Power Conquest" / Creeper-style fluid battle system
	## Clean architecture for galaxy strategy + autonomous fluid battles + replays.

	# Teams
	_execute("""
		CREATE TABLE IF NOT EXISTS teams (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL,
			color TEXT,
			is_ai BOOLEAN DEFAULT FALSE
		);
	""")

	# Games (top-level campaign/save)
	_execute("""
		CREATE TABLE IF NOT EXISTS games (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT DEFAULT 'Power Conquest',
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			last_updated DATETIME DEFAULT CURRENT_TIMESTAMP,
			galaxy_width INTEGER NOT NULL,
			galaxy_height INTEGER NOT NULL,
			current_turn INTEGER DEFAULT 0,
			status TEXT DEFAULT 'ongoing'
		);
	""")

	# Galaxy Nodes (strategic map)
	_execute("""
		CREATE TABLE IF NOT EXISTS galaxy_nodes (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
			node_name TEXT NOT NULL,
			pos_x INTEGER NOT NULL,
			pos_y INTEGER NOT NULL,
			node_type INTEGER DEFAULT 0,
			UNIQUE(game_id, pos_x, pos_y)
		);
	""")

	# Battle Zones (each 2D fluid map)
	_execute("""
		CREATE TABLE IF NOT EXISTS battle_zones (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
			galaxy_node_id INTEGER REFERENCES galaxy_nodes(id) ON DELETE CASCADE,
			map_width INTEGER NOT NULL,
			map_height INTEGER NOT NULL,
			status TEXT DEFAULT 'ongoing',
			winner_team_id INTEGER NULL,
			last_simulated_turn INTEGER DEFAULT 0
		);
	""")

	# Home Bases (emitters for each team in a zone)
	_execute("""
		CREATE TABLE IF NOT EXISTS home_bases (
			id INTEGER PRIMARY KEY,
			battle_zone_id INTEGER REFERENCES battle_zones(id) ON DELETE CASCADE,
			team_id INTEGER REFERENCES teams(id),
			pos_x INTEGER NOT NULL,
			pos_y INTEGER NOT NULL,
			base_spawn_rate REAL DEFAULT 10.0,
			committed_troops INTEGER DEFAULT 0,
			current_stock REAL DEFAULT 0.0,
			UNIQUE(battle_zone_id, team_id)
		);
	""")

	# Grid Cells (the actual fluid simulation state)
	_execute("""
		CREATE TABLE IF NOT EXISTS grid_cells (
			battle_zone_id INTEGER REFERENCES battle_zones(id) ON DELETE CASCADE,
			x INTEGER NOT NULL,
			y INTEGER NOT NULL,
			terrain_type INTEGER DEFAULT 0,
			elevation REAL DEFAULT 0.0,
			power_team1 REAL DEFAULT 0.0,
			power_team2 REAL DEFAULT 0.0,
			owner_team_id INTEGER NULL,
			PRIMARY KEY (battle_zone_id, x, y)
		);
	""")

	# Turns
	_execute("""
		CREATE TABLE IF NOT EXISTS turns (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
			turn_number INTEGER NOT NULL,
			started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(game_id, turn_number)
		);
	""")

	# Troop Deployments (player's main decision)
	_execute("""
		CREATE TABLE IF NOT EXISTS troop_deployments (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			turn_id INTEGER REFERENCES turns(id) ON DELETE CASCADE,
			battle_zone_id INTEGER REFERENCES battle_zones(id) ON DELETE CASCADE,
			team_id INTEGER REFERENCES teams(id),
			troops_sent INTEGER NOT NULL DEFAULT 0,
			deployed_at DATETIME DEFAULT CURRENT_TIMESTAMP
		);
	""")

	# Replay Events (for fluid battle replays)
	_execute("""
		CREATE TABLE IF NOT EXISTS replay_events (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			battle_zone_id INTEGER REFERENCES battle_zones(id) ON DELETE CASCADE,
			turn_number INTEGER NOT NULL,
			step INTEGER NOT NULL,
			event_type TEXT NOT NULL,
			x INTEGER NOT NULL,
			y INTEGER NOT NULL,
			team_id INTEGER NULL,
			power_delta REAL,
			opponent_power_delta REAL DEFAULT 0.0,
			new_owner_team_id INTEGER NULL,
			metadata TEXT NULL
		);
	""")

	# Indexes for performance
	_execute("CREATE INDEX IF NOT EXISTS idx_battle_zone_cells ON grid_cells (battle_zone_id, x, y);")
	_execute("CREATE INDEX IF NOT EXISTS idx_replay_battle_turn ON replay_events (battle_zone_id, turn_number, step);")
	_execute("CREATE INDEX IF NOT EXISTS idx_deployments_zone ON troop_deployments (battle_zone_id, turn_id);")
	_execute("CREATE INDEX IF NOT EXISTS idx_galaxy_nodes_game ON galaxy_nodes (game_id);")

	# Seed default teams if they don't exist
	var team_count: int = int(_query("SELECT COUNT(*) as c FROM teams")[0].get("c", 0))
	if team_count == 0:
		_execute("INSERT INTO teams (id, name, color, is_ai) VALUES (1, 'Player', '#4A90E2', 0);")
		_execute("INSERT INTO teams (id, name, color, is_ai) VALUES (2, 'Enemy', '#E74C3C', 1);")


func _apply_schema_v6() -> void:
	## Per-frame pressure snapshots for faithful territory replay visuals.
	_add_column_if_missing("battle_tile_frames", "pressure_friendly", "BLOB")
	_add_column_if_missing("battle_tile_frames", "pressure_hostile", "BLOB")


func _add_column_if_missing(table: String, column: String, col_type: String) -> void:
	var rows := _query("PRAGMA table_info(%s)" % table)
	for row in rows:
		if str(row.get("name", "")) == column:
			return
	_execute("ALTER TABLE %s ADD COLUMN %s %s" % [table, column, col_type])


func _apply_schema_v7() -> void:
	## One packed blob per territory battle (fast load, fixed 0.5s/frame replay).
	_execute(
		"""
		CREATE TABLE IF NOT EXISTS battle_territory_replay (
			battle_id INTEGER PRIMARY KEY,
			grid_width INTEGER NOT NULL,
			grid_height INTEGER NOT NULL,
			frame_count INTEGER NOT NULL,
			record_stride INTEGER NOT NULL DEFAULT 1,
			resolve_ms REAL NOT NULL DEFAULT 0,
			tape_blob BLOB NOT NULL
		);
		"""
	)


func _apply_schema_v8() -> void:
	## Per-tile elevation for uphill/downhill power flow (0.0–1.0 normalized).
	_add_column_if_missing("battle_tiles", "height", "REAL NOT NULL DEFAULT 0.5")


# --- Legacy import ---

func _import_legacy_profile_if_needed() -> void:
	var rows := _query("SELECT id FROM profile WHERE id = 1")
	if not rows.is_empty():
		return
	if FileAccess.file_exists(PROFILE_JSON_PATH):
		var file := FileAccess.open(PROFILE_JSON_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_save_profile_dict(parsed)
				return
	_save_profile_dict({"command_tokens": 0, "unlocked_classes": [0, 1]})


# --- Profile (SaveManager API) ---

func SyncProfileToSaveManager() -> void:
	var sm: Node = get_tree().root.get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var row := _load_profile_row()
	sm.command_tokens = int(row.get("command_tokens", 0))
	sm.carrier_biomass = int(row.get("carrier_biomass", 0))
	sm.total_runs = int(row.get("total_runs", 0))
	sm.total_ops_cleared = int(row.get("total_ops_cleared", 0))
	sm.best_run_depth = int(row.get("best_run_depth", 0))
	sm.unlocked_classes = _parse_int_array(row.get("unlocked_classes", "[0,1]"))
	sm.unlocked_portraits = _parse_string_array(row.get("unlocked_portraits", "[]"))
	sm.discovered_modifiers = _parse_string_array(row.get("discovered_modifiers", "[]"))
	sm.discovered_enemies = _parse_string_array(row.get("discovered_enemies", "[]"))
	sm.discovered_objectives = _parse_string_array(row.get("discovered_objectives", "[]"))
	sm.daily_best_date = str(row.get("daily_best_date", ""))
	sm.daily_best_ops = int(row.get("daily_best_ops", 0))
	sm.daily_best_kia = int(row.get("daily_best_kia", 999))
	sm.daily_best_time = float(row.get("daily_best_time", 999999.0))
	sm.ascension_level = int(row.get("ascension_level", 0))
	sm.codex_achievements = _parse_string_array(row.get("codex_achievements", "[]"))


func SaveProfileFromSaveManager() -> void:
	var sm: Node = get_tree().root.get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	_save_profile_dict({
		"command_tokens": sm.command_tokens,
		"carrier_biomass": sm.carrier_biomass,
		"total_runs": sm.total_runs,
		"total_ops_cleared": sm.total_ops_cleared,
		"best_run_depth": sm.best_run_depth,
		"unlocked_classes": sm.unlocked_classes,
		"unlocked_portraits": sm.unlocked_portraits,
		"discovered_modifiers": sm.discovered_modifiers,
		"discovered_enemies": sm.discovered_enemies,
		"discovered_objectives": sm.discovered_objectives,
		"daily_best_date": sm.daily_best_date,
		"daily_best_ops": sm.daily_best_ops,
		"daily_best_kia": sm.daily_best_kia,
		"daily_best_time": sm.daily_best_time,
		"ascension_level": sm.ascension_level,
		"codex_achievements": sm.codex_achievements,
	})


func _load_profile_row() -> Dictionary:
	var rows := _query("SELECT * FROM profile WHERE id = 1")
	if rows.is_empty():
		_save_profile_dict({"command_tokens": 0, "unlocked_classes": [0, 1]})
		rows = _query("SELECT * FROM profile WHERE id = 1")
	return rows[0] if not rows.is_empty() else {}


func _save_profile_dict(data: Dictionary) -> void:
	_execute(
		"""
		INSERT INTO profile (
			id, command_tokens, carrier_biomass, total_runs, total_ops_cleared, best_run_depth,
			unlocked_classes, unlocked_portraits, discovered_modifiers, discovered_enemies,
			discovered_objectives, daily_best_date, daily_best_ops, daily_best_kia, daily_best_time,
			ascension_level, codex_achievements
		) VALUES (1,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET
			command_tokens=excluded.command_tokens,
			carrier_biomass=excluded.carrier_biomass,
			total_runs=excluded.total_runs,
			total_ops_cleared=excluded.total_ops_cleared,
			best_run_depth=excluded.best_run_depth,
			unlocked_classes=excluded.unlocked_classes,
			unlocked_portraits=excluded.unlocked_portraits,
			discovered_modifiers=excluded.discovered_modifiers,
			discovered_enemies=excluded.discovered_enemies,
			discovered_objectives=excluded.discovered_objectives,
			daily_best_date=excluded.daily_best_date,
			daily_best_ops=excluded.daily_best_ops,
			daily_best_kia=excluded.daily_best_kia,
			daily_best_time=excluded.daily_best_time,
			ascension_level=excluded.ascension_level,
			codex_achievements=excluded.codex_achievements
		""",
		[
			data.get("command_tokens", 0),
			data.get("carrier_biomass", 0),
			data.get("total_runs", 0),
			data.get("total_ops_cleared", 0),
			data.get("best_run_depth", 0),
			_json_str(data.get("unlocked_classes", [0, 1])),
			_json_str(data.get("unlocked_portraits", [])),
			_json_str(data.get("discovered_modifiers", [])),
			_json_str(data.get("discovered_enemies", [])),
			_json_str(data.get("discovered_objectives", [])),
			data.get("daily_best_date", ""),
			data.get("daily_best_ops", 0),
			data.get("daily_best_kia", 999),
			data.get("daily_best_time", 999999.0),
			data.get("ascension_level", 0),
			_json_str(data.get("codex_achievements", [])),
		]
	)


# --- Commander runs (RunState API) ---

func SaveCommanderRun(run_data: Dictionary) -> int:
	_execute("UPDATE commander_runs SET is_active = 0")
	_execute(
		"""
		INSERT INTO commander_runs (
			commander_id, run_seed, run_credits, turn_index, is_active, pending_battle_node_id
		) VALUES (?,?,?,?,1,?)
		""",
		[
			run_data.get("commander_id", "logistician"),
			run_data.get("run_seed", 0),
			run_data.get("run_credits", 0),
			run_data.get("turn_index", 0),
			run_data.get("pending_battle_node_id", ""),
		]
	)
	var run_id: int = _last_insert_id()
	_execute(
		"""
		INSERT INTO run_snapshots (run_id, galaxy_json, army_json, resources_json)
		VALUES (?,?,?,?)
		ON CONFLICT(run_id) DO UPDATE SET
			galaxy_json=excluded.galaxy_json,
			army_json=excluded.army_json,
			resources_json=excluded.resources_json
		""",
		[
			run_id,
			_json_str(run_data.get("galaxy", {})),
			_json_str(run_data.get("army", {})),
			_json_str(run_data.get("resources", {})),
		]
	)
	return run_id


func LoadCommanderRun() -> Dictionary:
	var runs := _query(
		"SELECT * FROM commander_runs WHERE is_active = 1 ORDER BY id DESC LIMIT 1"
	)
	if runs.is_empty():
		return {}
	var run: Dictionary = runs[0]
	var run_id: int = int(run.get("id", 0))
	var snap := _query("SELECT * FROM run_snapshots WHERE run_id = ?", [run_id])
	if snap.is_empty():
		return {}
	return {
		"commander_id": run.get("commander_id", "logistician"),
		"run_seed": run.get("run_seed", 0),
		"run_credits": run.get("run_credits", 0),
		"turn_index": run.get("turn_index", 0),
		"pending_battle_node_id": run.get("pending_battle_node_id", ""),
		"galaxy": _parse_dict(snap[0].get("galaxy_json", "{}")),
		"army": _parse_dict(snap[0].get("army_json", "{}")),
		"resources": _parse_dict(snap[0].get("resources_json", "{}")),
		"run_id": run_id,
	}


func GetActiveRunId() -> int:
	var runs := _query("SELECT id FROM commander_runs WHERE is_active = 1 ORDER BY id DESC LIMIT 1")
	if runs.is_empty():
		return 0
	return int(runs[0].get("id", 0))


# --- Battle queue ---

func LoadBattleQueue(run_id: int) -> Array:
	var rows := _query(
		"""
		SELECT q.id AS queue_id, q.resolved, q.label, b.*
		FROM battle_queue q
		JOIN battles b ON b.id = q.battle_id
		WHERE q.run_id = ? AND q.resolved = 0
		ORDER BY q.queue_order ASC
		""",
		[run_id]
	)
	var out: Array = []
	for row in rows:
		out.append(_row_to_queue_entry(row))
	return out


func PersistBattleQueue(run_id: int, queue: Array) -> void:
	for i in range(queue.size()):
		var entry: Dictionary = queue[i]
		if entry.has("battle_id") and int(entry.get("battle_id", 0)) > 0:
			continue
		var replay_json: String = _replay_json_for_entry(entry)
		entry["replay_json"] = replay_json
		var battle_id: int = _insert_battle(run_id, entry, replay_json)
		entry["battle_id"] = battle_id
		if entry.has("map_snapshot"):
			BattleSqlPersistLib.persist_from_entry(self, battle_id, entry)
		_execute(
			"""
			INSERT INTO battle_queue (run_id, battle_id, queue_order, resolved, label)
			VALUES (?,?,?,0,?)
			""",
			[run_id, battle_id, i, str(entry.get("label", ""))]
		)


func MarkQueueResolved(queue_id: int) -> void:
	_execute("UPDATE battle_queue SET resolved = 1 WHERE id = ?", [queue_id])


func _insert_battle(run_id: int, entry: Dictionary, replay_json: String) -> int:
	_execute(
		"""
		INSERT INTO battles (
			run_id, node_id, terrain_tag, player_force, enemy_force, map_seed,
			player_won, player_losses, enemy_losses, turns, resolve_ms, resolve_mode, replay_json
		) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
		""",
		[
			run_id,
			entry.get("node_id", ""),
			entry.get("terrain_tag", "open_field"),
			entry.get("player_force", 0),
			entry.get("enemy_force", 0),
			entry.get("map_seed", 0),
			1 if bool(entry.get("player_won", false)) else 0,
			entry.get("player_losses", 0),
			entry.get("enemy_losses", 0),
			entry.get("turns", 0),
			entry.get("resolve_ms", 0.0),
			entry.get("resolve_mode", "tactical"),
			replay_json,
		]
	)
	return _last_insert_id()


# --- Tactical battle SQL (Dominions-style: map + units + moves are canonical) ---

func has_tactical_battle_data(battle_id: int) -> bool:
	var rows := _query(
		"SELECT battle_id FROM battle_maps WHERE battle_id = ? LIMIT 1",
		[battle_id],
	)
	if rows.is_empty():
		return false
	return count_battle_units(battle_id) > 0


func has_territory_battle_data(battle_id: int) -> bool:
	if battle_id <= 0:
		return false
	var map_rows := _query(
		"SELECT battle_id FROM battle_maps WHERE battle_id = ? LIMIT 1",
		[battle_id],
	)
	if map_rows.is_empty():
		return false
	return has_territory_replay_pack(battle_id) or count_battle_tile_frames(battle_id) > 0


func has_territory_replay_pack(battle_id: int) -> bool:
	var rows := _query(
		"SELECT battle_id FROM battle_territory_replay WHERE battle_id = ? LIMIT 1",
		[battle_id],
	)
	return not rows.is_empty()


func has_battle_replay_data(battle_id: int) -> bool:
	return has_territory_battle_data(battle_id) or has_tactical_battle_data(battle_id)


func clear_territory_battle_data(battle_id: int) -> void:
	_execute("DELETE FROM battle_territory_replay WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_tile_frames WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_rounds WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_meta WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_tiles WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_maps WHERE battle_id = ?", [battle_id])


func clear_tactical_battle_data(battle_id: int) -> void:
	_execute("DELETE FROM battle_tile_frames WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_unit_moves WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_unit_state WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_rounds WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_units WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_tiles WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_meta WHERE battle_id = ?", [battle_id])
	_execute("DELETE FROM battle_maps WHERE battle_id = ?", [battle_id])


func insert_battle_map(battle_id: int, map_data, map_snap: Dictionary) -> bool:
	return _execute(
		"""
		INSERT OR REPLACE INTO battle_maps (
			battle_id, grid_width, grid_height, cell_size, contact_column,
			map_seed, terrain_tag, map_json
		) VALUES (?,?,?,?,?,?,?,?)
		""",
		[
			battle_id,
			map_data.grid_width,
			map_data.grid_height,
			map_data.cell_size,
			map_data.contact_column,
			map_data.map_seed,
			map_data.terrain_tag,
			_json_str(map_snap),
		],
	)


func insert_battle_tiles(battle_id: int, map_data) -> bool:
	_execute("BEGIN TRANSACTION")
	var ok := true
	for gy in range(map_data.grid_height):
		for gx in range(map_data.grid_width):
			var tile_id: int = map_data.cell_index(gx, gy)
			var terrain: int = map_data.get_cell_terrain(gx, gy)
			var blocked: int = 1 if map_data.is_cell_blocked(gx, gy) else 0
			var cover: int = 0
			if tile_id < map_data.cover_cells.size():
				cover = int(map_data.cover_cells[tile_id])
			if not _execute(
				"""
				INSERT INTO battle_tiles (
					battle_id, tile_id, gx, gy, terrain, blocked, cover, move_cost, defense, height
				) VALUES (?,?,?,?,?,?,?,?,?,?)
				""",
				[
					battle_id,
					tile_id,
					gx,
					gy,
					terrain,
					blocked,
					cover,
					map_data.get_move_cost(gx, gy),
					map_data.get_defense(gx, gy),
					map_data.get_tile_height(gx, gy),
				],
			):
				ok = false
				break
		if not ok:
			break
	if ok:
		_execute("COMMIT")
	else:
		_execute("ROLLBACK")
	return ok


func insert_battle_units(battle_id: int, frame0: Dictionary, unit_count: int) -> bool:
	var gx_arr = frame0.get("grid_x", PackedInt32Array())
	var gy_arr = frame0.get("grid_y", PackedInt32Array())
	var hp_arr = frame0.get("health", PackedFloat32Array())
	var flags_arr = frame0.get("flags", PackedInt32Array())
	_execute("BEGIN TRANSACTION")
	var ok := true
	for i in range(unit_count):
		var side: int = 0
		if i < flags_arr.size():
			# Side not in frame — infer from spawn column vs contact later; store uses separate query
			pass
		var max_hp: float = float(hp_arr[i]) if i < hp_arr.size() else 1.0
		if not _execute(
			"""
			INSERT INTO battle_units (battle_id, unit_index, side, archetype, max_hp, unit_size)
			VALUES (?,?,?,?,?,?)
			""",
			[battle_id, i, side, 0, max_hp, 1],
		):
			ok = false
			break
	if ok:
		_execute("COMMIT")
	else:
		_execute("ROLLBACK")
	# Patch sides from frame0 grid position (friendly left of contact)
	var map_rows := _query(
		"SELECT contact_column, grid_width FROM battle_maps WHERE battle_id = ?",
		[battle_id],
	)
	var contact_col: int = 32
	if not map_rows.is_empty():
		contact_col = int(map_rows[0].get("contact_column", 32))
	for i in range(unit_count):
		var gx: int = int(gx_arr[i]) if i < gx_arr.size() else 0
		var side_val: int = 0 if gx < contact_col else 1
		_execute(
			"UPDATE battle_units SET side = ? WHERE battle_id = ? AND unit_index = ?",
			[side_val, battle_id, i],
		)
	return ok


func insert_battle_round(
	battle_id: int,
	frame_index: int,
	round_index: int,
	friendly_living: int,
	hostile_living: int,
) -> void:
	_execute(
		"""
		INSERT OR REPLACE INTO battle_rounds (
			battle_id, frame_index, round_index, friendly_living, hostile_living
		) VALUES (?,?,?,?,?)
		""",
		[battle_id, frame_index, round_index, friendly_living, hostile_living],
	)


func insert_battle_unit_states(
	battle_id: int,
	frame_index: int,
	map_data,
	frame: Dictionary,
	unit_count: int,
) -> void:
	var gx_arr = frame.get("grid_x", PackedInt32Array())
	var gy_arr = frame.get("grid_y", PackedInt32Array())
	var hp_arr = frame.get("health", PackedFloat32Array())
	var flags_arr = frame.get("flags", PackedInt32Array())
	var routed_arr = frame.get("routed", PackedInt32Array())
	var tier_arr = frame.get("tier", PackedInt32Array())
	_execute("BEGIN TRANSACTION")
	for i in range(unit_count):
		if i >= gx_arr.size() or i >= gy_arr.size():
			continue
		var gx: int = int(gx_arr[i])
		var gy: int = int(gy_arr[i])
		var tile_id: int = map_data.cell_index(gx, gy)
		var hp: float = float(hp_arr[i]) if i < hp_arr.size() else 0.0
		var flags: int = int(flags_arr[i]) if i < flags_arr.size() else 0
		var alive: int = 1 if (flags & 1) != 0 else 0
		var routed: int = int(routed_arr[i]) if i < routed_arr.size() else 0
		var tier: int = int(tier_arr[i]) if i < tier_arr.size() else 0
		_execute(
			"""
			INSERT OR REPLACE INTO battle_unit_state (
				battle_id, frame_index, unit_index, tile_id, gx, gy, hp, alive, routed, tier, flags
			) VALUES (?,?,?,?,?,?,?,?,?,?,?)
			""",
			[battle_id, frame_index, i, tile_id, gx, gy, hp, alive, routed, tier, flags],
		)
	_execute("COMMIT")


func insert_battle_unit_move(
	battle_id: int,
	frame_index: int,
	round_index: int,
	unit_index: int,
	from_tile_id: int,
	to_tile_id: int,
) -> void:
	_execute(
		"""
		INSERT INTO battle_unit_moves (
			battle_id, frame_index, round_index, unit_index, from_tile_id, to_tile_id
		) VALUES (?,?,?,?,?,?)
		""",
		[battle_id, frame_index, round_index, unit_index, from_tile_id, to_tile_id],
	)


func insert_battle_tile_frame(
	battle_id: int,
	frame_index: int,
	owners: PackedByteArray,
	pressure_friendly: PackedByteArray = PackedByteArray(),
	pressure_hostile: PackedByteArray = PackedByteArray(),
) -> void:
	if owners.is_empty():
		return
	_execute(
		"""
		INSERT OR REPLACE INTO battle_tile_frames (
			battle_id, frame_index, owners, pressure_friendly, pressure_hostile
		) VALUES (?,?,?,?,?)
		""",
		[battle_id, frame_index, owners, pressure_friendly, pressure_hostile],
	)


func load_battle_tile_frames_grouped(battle_id: int) -> Dictionary:
	var rows := _query(
		"""
		SELECT frame_index, owners, pressure_friendly, pressure_hostile
		FROM battle_tile_frames
		WHERE battle_id = ? ORDER BY frame_index ASC
		""",
		[battle_id],
	)
	var by_frame: Dictionary = {}
	for row in rows:
		var fi: int = int(row.get("frame_index", 0))
		var pack: Dictionary = {}
		var owners = row.get("owners", PackedByteArray())
		if owners is PackedByteArray:
			pack["owners"] = owners
		elif typeof(owners) == TYPE_STRING:
			pack["owners"] = owners.to_utf8_buffer()
		var pf = row.get("pressure_friendly", PackedByteArray())
		if pf is PackedByteArray and not pf.is_empty():
			pack["pressure_f"] = pf
		var ph = row.get("pressure_hostile", PackedByteArray())
		if ph is PackedByteArray and not ph.is_empty():
			pack["pressure_h"] = ph
		by_frame[fi] = pack
	return by_frame


func insert_territory_replay_pack(battle_id: int, map_data, tape) -> bool:
	if battle_id <= 0 or map_data == null or tape == null or tape.frame_count() == 0:
		return false
	var blob: PackedByteArray = BattleReplayPackLib.pack_tape(
		tape, map_data.grid_width, map_data.grid_height
	)
	if blob.is_empty():
		return false
	return _execute(
		"""
		INSERT OR REPLACE INTO battle_territory_replay (
			battle_id, grid_width, grid_height, frame_count,
			record_stride, resolve_ms, tape_blob
		) VALUES (?,?,?,?,?,?,?)
		""",
		[
			battle_id,
			map_data.grid_width,
			map_data.grid_height,
			tape.frame_count(),
			tape.record_stride,
			tape.resolve_ms,
			blob,
		],
	)


func load_territory_replay_pack(battle_id: int):
	var rows := _query(
		"SELECT tape_blob FROM battle_territory_replay WHERE battle_id = ? LIMIT 1",
		[battle_id],
	)
	if rows.is_empty():
		return null
	var blob = rows[0].get("tape_blob", PackedByteArray())
	if not blob is PackedByteArray or blob.is_empty():
		return null
	return BattleReplayPackLib.unpack_tape(blob)


func count_battle_tile_frames(battle_id: int) -> int:
	var rows := _query(
		"SELECT COUNT(*) AS n FROM battle_tile_frames WHERE battle_id = ?",
		[battle_id],
	)
	if rows.is_empty():
		return 0
	return int(rows[0].get("n", 0))


func insert_battle_meta(
	battle_id: int,
	frame_count: int,
	record_stride: int,
	round_duration: float,
	resolve_ms: float,
) -> void:
	_execute(
		"""
		INSERT OR REPLACE INTO battle_meta (
			battle_id, frame_count, record_stride, round_duration, resolve_ms
		) VALUES (?,?,?,?,?)
		""",
		[battle_id, frame_count, record_stride, round_duration, resolve_ms],
	)


func load_battle_map_snapshot(battle_id: int) -> Dictionary:
	var rows := _query(
		"SELECT map_json FROM battle_maps WHERE battle_id = ? LIMIT 1",
		[battle_id],
	)
	if rows.is_empty():
		return {}
	return _parse_dict(rows[0].get("map_json", "{}"))


## Copy per-tile height from battle_tiles into map_data (for flow / replay after SQL load).
func apply_battle_tile_heights_to_map(battle_id: int, map_data) -> bool:
	if battle_id <= 0 or map_data == null:
		return false
	var rows := _query(
		"SELECT tile_id, height FROM battle_tiles WHERE battle_id = ? ORDER BY tile_id ASC",
		[battle_id],
	)
	if rows.is_empty():
		return false
	var n: int = map_data.grid_width * map_data.grid_height
	if n <= 0:
		return false
	map_data.tile_height.resize(n)
	for row in rows:
		var tid: int = int(row.get("tile_id", -1))
		if tid < 0 or tid >= n:
			continue
		map_data.tile_height[tid] = clampf(float(row.get("height", 0.5)), 0.0, 1.0)
	return true


func load_battle_meta(battle_id: int) -> Dictionary:
	var rows := _query(
		"SELECT frame_count, record_stride, round_duration, resolve_ms FROM battle_meta WHERE battle_id = ? LIMIT 1",
		[battle_id],
	)
	if rows.is_empty():
		return {}
	return rows[0]


func count_battle_units(battle_id: int) -> int:
	var rows := _query(
		"SELECT COUNT(*) AS n FROM battle_units WHERE battle_id = ?",
		[battle_id],
	)
	if rows.is_empty():
		return 0
	return int(rows[0].get("n", 0))


func load_battle_rounds(battle_id: int) -> Array:
	return _query(
		"""
		SELECT frame_index, round_index, friendly_living, hostile_living
		FROM battle_rounds WHERE battle_id = ? ORDER BY frame_index ASC
		""",
		[battle_id],
	)


func load_battle_unit_states_grouped(battle_id: int, unit_count: int) -> Dictionary:
	var rows := _query(
		"""
		SELECT frame_index, unit_index, tile_id, gx, gy, hp, alive, routed, tier, flags
		FROM battle_unit_state WHERE battle_id = ? ORDER BY frame_index ASC, unit_index ASC
		""",
		[battle_id],
	)
	var by_frame: Dictionary = {}
	for row in rows:
		var fi: int = int(row.get("frame_index", 0))
		if not by_frame.has(fi):
			by_frame[fi] = _empty_frame(unit_count)
		var frame: Dictionary = by_frame[fi]
		var ui: int = int(row.get("unit_index", 0))
		if ui < 0 or ui >= unit_count:
			continue
		frame["grid_x"][ui] = int(row.get("gx", 0))
		frame["grid_y"][ui] = int(row.get("gy", 0))
		frame["health"][ui] = float(row.get("hp", 0.0))
		frame["flags"][ui] = int(row.get("flags", 0))
		if int(row.get("alive", 0)) == 0:
			frame["flags"][ui] &= ~UnitSimulationStoreLib.FLAG_ALIVE
		else:
			frame["flags"][ui] |= UnitSimulationStoreLib.FLAG_ALIVE
		frame["routed"][ui] = int(row.get("routed", 0))
		frame["tier"][ui] = int(row.get("tier", 0))
	return by_frame


func load_battle_unit_states_for_frame(
	battle_id: int,
	frame_index: int,
	unit_count: int,
	map_data = null,
) -> Dictionary:
	var rows := _query(
		"""
		SELECT unit_index, tile_id, gx, gy, hp, alive, routed, tier, flags
		FROM battle_unit_state
		WHERE battle_id = ? AND frame_index = ?
		ORDER BY unit_index ASC
		""",
		[battle_id, frame_index],
	)
	var frame := _empty_frame(unit_count)
	for row in rows:
		var ui: int = int(row.get("unit_index", 0))
		if ui < 0 or ui >= unit_count:
			continue
		frame["grid_x"][ui] = int(row.get("gx", 0))
		frame["grid_y"][ui] = int(row.get("gy", 0))
		frame["health"][ui] = float(row.get("hp", 0.0))
		frame["flags"][ui] = int(row.get("flags", 0))
		frame["routed"][ui] = int(row.get("routed", 0))
		frame["tier"][ui] = int(row.get("tier", 0))
		if map_data != null:
			frame["positions"][ui] = map_data.cell_center(
				int(row.get("gx", 0)), int(row.get("gy", 0))
			)
	return frame


func load_battle_moves_for_frame(battle_id: int, frame_index: int) -> Array:
	return _query(
		"""
		SELECT unit_index, from_tile_id, to_tile_id, round_index
		FROM battle_unit_moves
		WHERE battle_id = ? AND frame_index = ?
		ORDER BY unit_index ASC
		""",
		[battle_id, frame_index],
	)


func load_battle_result_row(battle_id: int) -> Dictionary:
	var rows := _query(
		"SELECT player_won, turns FROM battles WHERE id = ? LIMIT 1",
		[battle_id],
	)
	if rows.is_empty():
		return {}
	return rows[0]


# ============================================================
# === REVOLUTIONARY "POWER CONQUEST" SCHEMA HELPERS (v5) ===
# ============================================================

func create_new_game(name: String, galaxy_width: int, galaxy_height: int) -> int:
	_execute(
		"""
		INSERT INTO games (name, galaxy_width, galaxy_height, current_turn, status)
		VALUES (?, ?, ?, 0, 'ongoing')
		""",
		[name, galaxy_width, galaxy_height]
	)
	return _last_insert_id()


func create_galaxy_node(game_id: int, node_name: String, pos_x: int, pos_y: int, node_type: int = 0) -> int:
	_execute(
		"""
		INSERT OR IGNORE INTO galaxy_nodes (game_id, node_name, pos_x, pos_y, node_type)
		VALUES (?, ?, ?, ?, ?)
		""",
		[game_id, node_name, pos_x, pos_y, node_type]
	)
	var rows := _query(
		"SELECT id FROM galaxy_nodes WHERE game_id = ? AND pos_x = ? AND pos_y = ? LIMIT 1",
		[game_id, pos_x, pos_y]
	)
	if rows.is_empty():
		return 0
	return int(rows[0].get("id", 0))


func create_battle_zone(game_id: int, galaxy_node_id: int, map_width: int, map_height: int) -> int:
	_execute(
		"""
		INSERT INTO battle_zones (game_id, galaxy_node_id, map_width, map_height, status)
		VALUES (?, ?, ?, ?, 'ongoing')
		""",
		[game_id, galaxy_node_id, map_width, map_height]
	)
	return _last_insert_id()


func get_or_create_home_base(battle_zone_id: int, team_id: int, pos_x: int, pos_y: int, spawn_rate: float = 10.0) -> int:
	var rows := _query(
		"SELECT id FROM home_bases WHERE battle_zone_id = ? AND team_id = ? LIMIT 1",
		[battle_zone_id, team_id]
	)
	if not rows.is_empty():
		return int(rows[0].get("id", 0))

	_execute(
		"""
		INSERT INTO home_bases (battle_zone_id, team_id, pos_x, pos_y, base_spawn_rate)
		VALUES (?, ?, ?, ?, ?)
		""",
		[battle_zone_id, team_id, pos_x, pos_y, spawn_rate]
	)
	return _last_insert_id()


func save_grid_cell(battle_zone_id: int, x: int, y: int, terrain_type: int, elevation: float,
					power_team1: float, power_team2: float, owner_team_id: int) -> void:
	_execute(
		"""
		INSERT OR REPLACE INTO grid_cells 
		(battle_zone_id, x, y, terrain_type, elevation, power_team1, power_team2, owner_team_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""",
		[battle_zone_id, x, y, terrain_type, elevation, power_team1, power_team2, owner_team_id]
	)


func record_replay_event(battle_zone_id: int, turn_number: int, step: int, event_type: String,
						 x: int, y: int, team_id: int = 0, power_delta: float = 0.0,
						 opponent_power_delta: float = 0.0, new_owner_team_id: int = 0,
						 metadata: String = "") -> void:
	_execute(
		"""
		INSERT INTO replay_events 
		(battle_zone_id, turn_number, step, event_type, x, y, team_id, power_delta, opponent_power_delta, new_owner_team_id, metadata)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		""",
		[battle_zone_id, turn_number, step, event_type, x, y, team_id, power_delta, opponent_power_delta, new_owner_team_id, metadata]
	)


# --- Grid state persistence for fluid simulation (B) ---

func load_battle_zone_grid(battle_zone_id: int) -> Dictionary:
	"""Returns { width, height, cells: Array[Dictionary] }"""
	var rows := _query(
		"""
		SELECT x, y, terrain_type, elevation, power_team1, power_team2, owner_team_id
		FROM grid_cells 
		WHERE battle_zone_id = ?
		ORDER BY y, x
		""",
		[battle_zone_id]
	)

	if rows.is_empty():
		return {}

	var width := 0
	var height := 0
	for row in rows:
		width = max(width, int(row.get("x", 0)) + 1)
		height = max(height, int(row.get("y", 0)) + 1)

	return {
		"width": width,
		"height": height,
		"cells": rows
	}


func save_battle_zone_grid(battle_zone_id: int, width: int, height: int, cells: Array) -> void:
	"""Expects cells as Array of {x, y, terrain_type, elevation, power_team1, power_team2, owner_team_id}"""
	# Clear existing
	_execute("DELETE FROM grid_cells WHERE battle_zone_id = ?", [battle_zone_id])

	for cell in cells:
		save_grid_cell(
			battle_zone_id,
			int(cell.get("x", 0)),
			int(cell.get("y", 0)),
			int(cell.get("terrain_type", 0)),
			float(cell.get("elevation", 0.0)),
			float(cell.get("power_team1", 0.0)),
			float(cell.get("power_team2", 0.0)),
			int(cell.get("owner_team_id", 0))
		)


func get_home_bases_for_zone(battle_zone_id: int) -> Array:
	return _query(
		"""
		SELECT id, team_id, pos_x, pos_y, base_spawn_rate, committed_troops, current_stock
		FROM home_bases 
		WHERE battle_zone_id = ?
		""",
		[battle_zone_id]
	)


func get_galaxy_nodes(game_id: int) -> Array:
	"""Returns all galaxy nodes for a game, useful for rendering the strategic map."""
	return _query(
		"""
		SELECT id, node_name, pos_x, pos_y, node_type
		FROM galaxy_nodes 
		WHERE game_id = ?
		ORDER BY pos_y, pos_x
		""",
		[game_id]
	)


func get_battle_zones_for_game(game_id: int) -> Array:
	"""Returns battle zones linked to their galaxy nodes (great for the strategic map UI)."""
	return _query(
		"""
		SELECT 
			bz.id as battle_zone_id,
			bz.map_width,
			bz.map_height,
			bz.status,
			bz.winner_team_id,
			gn.id as galaxy_node_id,
			gn.node_name,
			gn.pos_x,
			gn.pos_y,
			gn.node_type
		FROM battle_zones bz
		JOIN galaxy_nodes gn ON gn.id = bz.galaxy_node_id
		WHERE bz.game_id = ?
		ORDER BY gn.pos_y, gn.pos_x
		""",
		[game_id]
	)


func load_full_battle_zone_state(battle_zone_id: int) -> Dictionary:
	"""Loads everything needed to run the simple fluid simulation in memory."""
	var zone_rows: Array[Dictionary] = _query("SELECT map_width, map_height FROM battle_zones WHERE id = ? LIMIT 1", [battle_zone_id])
	if zone_rows.is_empty():
		return {}

	var width: int = int(zone_rows[0].get("map_width", 0))
	var height: int = int(zone_rows[0].get("map_height", 0))

	var grid: Dictionary = load_battle_zone_grid(battle_zone_id)
	var home_bases: Array = get_home_bases_for_zone(battle_zone_id)

	return {
		"battle_zone_id": battle_zone_id,
		"width": width,
		"height": height,
		"grid_cells": grid.get("cells", []),
		"home_bases": home_bases
	}


func save_full_battle_zone_state(battle_zone_id: int, width: int, height: int, cells: Array, home_bases: Array) -> void:
	save_battle_zone_grid(battle_zone_id, width, height, cells)

	# Update home bases stock / committed troops if needed
	for base in home_bases:
		_execute(
			"""
			UPDATE home_bases 
			SET current_stock = ?, committed_troops = ?
			WHERE id = ?
			""",
			[float(base.get("current_stock", 0)), int(base.get("committed_troops", 0)), int(base.get("id", 0))]
		)


func simulate_and_record_battle_step(battle_zone_id: int, turn_number: int, step: int) -> Dictionary:
	"""
	Runs one step of the simple fluid simulation using the new v5 schema
	and records basic events.
	"""
	var state: Dictionary = load_full_battle_zone_state(battle_zone_id)
	if state.is_empty():
		return {"error": "No state found for battle zone"}

	var sim: SimpleFluidSimulator = SimpleFluidSimulator.new()
	sim.load_from_state(state)

	var events: Array = sim.step()

	var new_state: Dictionary = sim.save_to_state()
	save_full_battle_zone_state(
		battle_zone_id,
		new_state.width,
		new_state.height,
		new_state.grid_cells,
		new_state.home_bases
	)

	# Record events returned by the simulator (captures, etc.)
	for ev in events:
		record_replay_event(
			battle_zone_id,
			turn_number,
			step,
			str(ev.get("type", "change")),
			int(ev.get("x", -1)),
			int(ev.get("y", -1)),
			0, 0.0, 0.0,
			int(ev.get("new_owner", 0)),
			""
		)

	# Record current ownership snapshot
	var percents := sim.get_ownership_percentages()
	record_replay_event(
		battle_zone_id,
		turn_number,
		step,
		"ownership",
		-1, -1,
		0,
		percents.get("team1", 0.0),
		percents.get("team2", 0.0),
		0,
		JSON.stringify(percents)
	)

	return {
		"battle_zone_id": battle_zone_id,
		"step": step,
		"ownership": percents
	}


func simulate_battle_zone_steps(battle_zone_id: int, steps: int, turn_number: int) -> Dictionary:
	"""
	Runs multiple simulation steps efficiently and records periodic snapshots.
	"""
	var state: Dictionary = load_full_battle_zone_state(battle_zone_id)
	if state.is_empty():
		return {"error": "No state"}

	var sim: SimpleFluidSimulator = SimpleFluidSimulator.new()
	sim.load_from_state(state)

	var last_percentages: Dictionary = {}

	for i in range(steps):
		var events: Array = sim.step()

		for ev in events:
			record_replay_event(
				battle_zone_id,
				turn_number,
				sim.step_count,
				str(ev.get("type", "change")),
				int(ev.get("x", -1)),
				int(ev.get("y", -1)),
				0, 0.0, 0.0,
				int(ev.get("new_owner", 0)),
				""
			)

		if i % 20 == 0 or i == steps - 1:
			var percs: Dictionary = sim.get_ownership_percentages()
			last_percentages = percs

			record_replay_event(
				battle_zone_id,
				turn_number,
				sim.step_count,
				"ownership",
				-1, -1,
				0,
				percs.get("team1", 0.0),
				percs.get("team2", 0.0),
				0,
				""
			)

	var final_state: Dictionary = sim.save_to_state()
	save_full_battle_zone_state(
		battle_zone_id,
		final_state.width,
		final_state.height,
		final_state.grid_cells,
		final_state.home_bases
	)

	return {
		"battle_zone_id": battle_zone_id,
		"steps_run": steps,
		"final_ownership": last_percentages
	}


# Basic turn-level simulation skeleton (2)
func run_turn_for_game(game_id: int, steps_per_zone: int = 200) -> Dictionary:
	"""
	High-level turn execution for the new Power Conquest system.
	- Increments turn
	- For every active battle zone, runs simulation steps
	- Returns summary
	"""
	var game_rows := _query("SELECT current_turn FROM games WHERE id = ? LIMIT 1", [game_id])
	if game_rows.is_empty():
		return {"error": "Game not found"}

	var current_turn := int(game_rows[0].get("current_turn", 0))
	var new_turn := current_turn + 1

	# Create turn record
	_execute(
		"INSERT INTO turns (game_id, turn_number) VALUES (?, ?)",
		[game_id, new_turn]
	)
	var turn_id := _last_insert_id()

	# Get all active battle zones for this game
	var zones := _query(
		"SELECT id FROM battle_zones WHERE game_id = ? AND status = 'ongoing'",
		[game_id]
	)

	var results := []
	for z in zones:
		var zid := int(z.get("id"))
		var result := simulate_battle_zone_steps(zid, steps_per_zone, new_turn)
		results.append(result)

	# Update game turn
	_execute("UPDATE games SET current_turn = ? WHERE id = ?", [new_turn, game_id])

	return {
		"game_id": game_id,
		"turn_number": new_turn,
		"zones_simulated": results.size(),
		"results": results
	}


# --- High-level initialization for new Power Conquest games (A) ---

func initialize_new_power_conquest_game(game_name: String, galaxy_width: int, galaxy_height: int, 
										battle_map_size: int = 64, num_nodes: int = 16) -> int:
	"""
	Creates a brand new game using the v5 Power Conquest schema.
	Generates a galaxy of nodes and sets up battle zones with home bases.
	"""
	var game_id: int = create_new_game(game_name, galaxy_width, galaxy_height)

	# Generate galaxy nodes in a loose grid pattern
	var nodes_per_row: int = int(sqrt(num_nodes))
	var node_spacing_x: int = max(2, galaxy_width / (nodes_per_row + 1))
	var node_spacing_y: int = max(2, galaxy_height / (nodes_per_row + 1))

	var node_ids: Array[int] = []
	var node_index: int = 0

	for row in range(nodes_per_row + 2):
		for col in range(nodes_per_row + 2):
			if node_index >= num_nodes:
				break
			var px: int = 1 + col * node_spacing_x + randi() % 3 - 1
			var py: int = 1 + row * node_spacing_y + randi() % 3 - 1
			px = clamp(px, 1, galaxy_width - 2)
			py = clamp(py, 1, galaxy_height - 2)

			var node_name: String = "Sector %02d" % (node_index + 1)
			var node_type: int = 0
			if node_index == 0:
				node_type = 1  # Starting capital

			var node_id: int = create_galaxy_node(game_id, node_name, px, py, node_type)
			node_ids.append(node_id)
			node_index += 1

	# Create a battle zone + home bases for each galaxy node
	for node_id in node_ids:
		var zone_id := create_battle_zone(game_id, node_id, battle_map_size, battle_map_size)

		# Home base for Player (team 1) - bottom left area
		var base1_x: int = 4 + randi() % 6
		var base1_y: int = battle_map_size - 8 - randi() % 6
		get_or_create_home_base(zone_id, 1, base1_x, base1_y, 12.0)

		# Home base for Enemy (team 2) - top right area
		var base2_x: int = battle_map_size - 8 - randi() % 6
		var base2_y: int = 4 + randi() % 6
		get_or_create_home_base(zone_id, 2, base2_x, base2_y, 12.0)

		# Seed initial grid cells
		_seed_initial_grid_cells(zone_id, battle_map_size)

	return game_id


func _seed_initial_grid_cells(battle_zone_id: int, size: int) -> void:
	# Seed neutral cells with slight elevation variation
	for y in range(size):
		for x in range(size):
			var elevation: float = randf_range(0.0, 1.0)
			# Slight mountain bias in center for interesting terrain
			var dist_from_center: int = abs(x - size/2) + abs(y - size/2)
			if dist_from_center < size * 0.2:
				elevation = max(elevation, randf_range(0.6, 1.0))

			var terrain: int = 0
			if elevation > 0.72:
				terrain = 2  # Mountain
			elif elevation > 0.45:
				terrain = 1  # Hills

			save_grid_cell(battle_zone_id, x, y, terrain, elevation, 0.0, 0.0, 0)

	# Claim home base areas for team 1 (bottom left)
	for y in range(size-10, size-2):
		for x in range(2, 10):
			if x < size and y < size:
				save_grid_cell(battle_zone_id, x, y, 0, 0.2, 5.0, 0.0, 1)

	# Claim home base areas for team 2 (top right)
	for y in range(2, 10):
		for x in range(size-10, size-2):
			if x >= 0 and y >= 0:
				save_grid_cell(battle_zone_id, x, y, 0, 0.2, 0.0, 5.0, 2)


func _empty_frame(unit_count: int) -> Dictionary:
	var positions := PackedVector2Array()
	var grid_x := PackedInt32Array()
	var grid_y := PackedInt32Array()
	var health := PackedFloat32Array()
	var flags := PackedInt32Array()
	var routed := PackedInt32Array()
	var tier := PackedInt32Array()
	positions.resize(unit_count)
	grid_x.resize(unit_count)
	grid_y.resize(unit_count)
	health.resize(unit_count)
	flags.resize(unit_count)
	routed.resize(unit_count)
	tier.resize(unit_count)
	return {
		"positions": positions,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"health": health,
		"flags": flags,
		"routed": routed,
		"tier": tier,
	}


func _row_to_queue_entry(row: Dictionary) -> Dictionary:
	var replay_text: String = str(row.get("replay_json", "{}"))
	var parsed = JSON.parse_string(replay_text)
	var tape: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var result: Dictionary = tape.get("result", {})
	var unit_analysis: Dictionary = result.get("unit_analysis", {})
	return {
		"queue_id": row.get("queue_id", 0),
		"replay_json": replay_text,
		"battle_id": row.get("id", 0),
		"node_id": row.get("node_id", ""),
		"label": row.get("label", ""),
		"terrain_tag": row.get("terrain_tag", "open_field"),
		"player_force": row.get("player_force", 0),
		"enemy_force": row.get("enemy_force", 0),
		"player_won": int(row.get("player_won", 0)) != 0,
		"player_losses": row.get("player_losses", 0),
		"enemy_losses": row.get("enemy_losses", 0),
		"turns": row.get("turns", 0),
		"resolve_ms": row.get("resolve_ms", 0.0),
		"resolve_mode": row.get("resolve_mode", "tactical"),
		"resolved": false,
		"tape": tape,
		"frame_count": tape.get("frame_count", 0),
		"sql_tactical": has_tactical_battle_data(int(row.get("id", 0))),
		"unit_analysis": unit_analysis,
	}


func _replay_json_for_entry(entry: Dictionary) -> String:
	if entry.has("replay_json"):
		var rj = entry.get("replay_json", "")
		if typeof(rj) == TYPE_STRING and not str(rj).is_empty():
			return str(rj)
	var tape = entry.get("tape", null)
	if typeof(tape) == TYPE_DICTIONARY:
		return JSON.stringify(tape)
	if tape != null and tape.has_method("to_dictionary"):
		return JSON.stringify(tape.call("to_dictionary"))
	return "{}"


# --- Helpers ---

func _json_str(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return v
	return JSON.stringify(v)


func _parse_dict(raw: Variant) -> Dictionary:
	var text: String = str(raw)
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _parse_int_array(raw: Variant) -> Array[int]:
	var parsed = JSON.parse_string(str(raw) if typeof(raw) == TYPE_STRING else JSON.stringify(raw))
	var out: Array[int] = []
	if typeof(parsed) == TYPE_ARRAY:
		for v in parsed:
			out.append(int(v))
	if out.is_empty():
		return [0, 1]
	return out


func _parse_string_array(raw: Variant) -> Array[String]:
	var parsed = JSON.parse_string(str(raw) if typeof(raw) == TYPE_STRING else JSON.stringify(raw))
	var out: Array[String] = []
	if typeof(parsed) == TYPE_ARRAY:
		for v in parsed:
			out.append(str(v))
	return out
