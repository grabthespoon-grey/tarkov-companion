extends Node

const SAVE_PATH = "user://save_data.json"
const SAVE_VERSION = 1

func save_game() -> void:
	var save_data = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"game_state": GameManager.game_state,
		"farm_state": _capture_farm_state(),
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SaveManager: corrupted save file")
		return

	var save_data = json.get_data()
	_restore_game_state(save_data)
	# _handle_offline_progress(save_data)  # offline farming — disabled, see below
	_restore_farm_state(save_data)

func _capture_farm_state() -> Dictionary:
	if not GameManager.game_state.operator.is_deployed:
		return {}
	return {
		"location_id": GameManager.game_state.operator.deploy_location,
		"efficiency": GameManager.get_farming_efficiency(),
		"elapsed": TimeManager._farm_elapsed,
		"duration": TimeManager._farm_duration,
	}

func _restore_game_state(save_data: Dictionary) -> void:
	var saved = save_data.get("game_state", {})
	_deep_merge(GameManager.game_state, saved)

func _handle_offline_progress(save_data: Dictionary) -> void:
	var last_save = save_data.get("timestamp", Time.get_unix_time_from_system())
	var raids = TimeManager.calculate_offline_raids(last_save)
	if raids <= 0:
		return

	var location_id = save_data.get("farm_state", {}).get("location_id", "factory")
	for _i in range(min(raids, 20)):
		var loot = LootSystem.roll_loot(location_id, 0.7)
		if not loot.get("failed", true):
			for item in loot.get("items", []):
				GameManager.game_state.inventory.append(item)
			GameManager.game_state.rubles += loot.get("rubles", 0)

func _restore_farm_state(save_data: Dictionary) -> void:
	var farm = save_data.get("farm_state", {})
	if farm.is_empty() or not GameManager.game_state.operator.is_deployed:
		return

	var elapsed = Time.get_unix_time_from_system() - save_data.get("timestamp", 0.0)
	elapsed += farm.get("elapsed", 0.0)
	TimeManager.resume_from_save(
		elapsed,
		farm.get("location_id", "factory"),
		farm.get("efficiency", 1.0),
		farm.get("duration", 600.0)
	)

func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if key in target and typeof(target[key]) == TYPE_DICTIONARY and typeof(source[key]) == TYPE_DICTIONARY:
			_deep_merge(target[key], source[key])
		else:
			target[key] = source[key]
