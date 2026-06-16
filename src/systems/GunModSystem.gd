extends Node

var _weapon_configs: Dictionary = {}

func _ready() -> void:
	_load_configs()

func _load_configs() -> void:
	var file = FileAccess.open("res://data/weapons/weapons.json", FileAccess.READ)
	if not file:
		push_error("GunModSystem: cannot open weapons.json")
		return
	var json = JSON.new()
	json.parse(file.get_as_text())
	for weapon in json.get_data():
		_weapon_configs[weapon["id"]] = weapon

func get_weapon_config(type_id: String) -> Dictionary:
	return _weapon_configs.get(type_id, {})

func can_attach_mod(weapon, mod) -> bool:
	if not weapon is Dictionary or not mod is Dictionary:
		return false
	var config = _weapon_configs.get(weapon.get("type_id", ""), {})
	if config.is_empty():
		return false
	var slot_type = mod.get("category", "")
	var allowed = config.get("mod_slots", {}).get(slot_type, [])
	return mod.get("mod_type", "") in allowed

func attach_mod(weapon, mod) -> bool:
	if not can_attach_mod(weapon, mod):
		return false
	var slot = mod.get("category", "")
	if "mods" not in weapon:
		weapon["mods"] = {}
	if slot in weapon["mods"]:
		GameManager.game_state.inventory.append(weapon["mods"][slot])
	weapon["mods"][slot] = mod
	GameManager.game_state.inventory.erase(mod)
	return true

func detach_mod(weapon, slot: String) -> Dictionary:
	if not weapon is Dictionary or "mods" not in weapon or slot not in weapon["mods"]:
		return {}
	var mod = weapon["mods"][slot]
	weapon["mods"].erase(slot)
	GameManager.game_state.inventory.append(mod)
	return mod

func get_available_slots(weapon) -> Array:
	if not weapon is Dictionary:
		return []
	var config = _weapon_configs.get(weapon.get("type_id", ""), {})
	return config.get("mod_slots", {}).keys()

func calculate_weapon_stats(weapon) -> Dictionary:
	if not weapon is Dictionary:
		return {}
	var config = _weapon_configs.get(weapon.get("type_id", ""), {})
	var stats = config.get("base_stats", {}).duplicate(true)
	for _slot in weapon.get("mods", {}):
		var mod = weapon["mods"][_slot]
		for stat in mod.get("stats", {}):
			if stat in stats:
				stats[stat] += mod["stats"][stat]
	return stats

func calculate_efficiency_bonus(weapon) -> float:
	if not weapon is Dictionary:
		return 0.0
	var total := 0.0
	for _slot in weapon.get("mods", {}):
		total += weapon["mods"][_slot].get("efficiency_bonus", 0.0)
	return clampf(total, 0.0, 0.5)

func get_compatible_mods(weapon, inventory: Array) -> Array:
	return inventory.filter(func(item): return can_attach_mod(weapon, item))
