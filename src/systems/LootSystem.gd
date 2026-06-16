extends Node

var _locations: Array = []
var _item_pool: Array = []

func _ready() -> void:
	_load_data()

func _load_data() -> void:
	_locations = _load_json("res://data/locations/locations.json")
	_item_pool  = _load_json("res://data/items/gun_mods.json")

func _load_json(path: String) -> Array:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("LootSystem: cannot open " + path)
		return []
	var json = JSON.new()
	json.parse(file.get_as_text())
	return json.get_data()

func get_location(location_id: String) -> Dictionary:
	for loc in _locations:
		if loc.get("id", "") == location_id:
			return loc
	return {}

func get_all_locations() -> Array:
	return _locations

func get_unlocked_locations(player_level: int) -> Array:
	return _locations.filter(func(loc):
		var req = loc.get("unlock_requirement", null)
		if req == null:
			return true
		return player_level >= req.get("level", 1)
	)

func roll_loot(location_id: String, efficiency: float, ammo_penalty: float = 0.0, loot_bonus: float = 0.0, fail_reduction: float = 0.0) -> Dictionary:
	var location = get_location(location_id)
	if location.is_empty():
		return {"failed": true, "reason": "invalid_location"}

	var danger = location.get("danger_level", 0.3)
	var fail_chance = clampf(
		danger * (1.0 - clampf(efficiency * 0.6, 0.0, 0.8)) + ammo_penalty - fail_reduction,
		0.0, 1.0
	)
	if randf() < fail_chance:
		return {
			"failed": true,
			"reason": "operator_lost",
			"danger_encountered": danger,
			"location_name": location.get("name", "Unknown"),
		}

	var count = roundi(
		randf_range(
			location.get("min_loot", 1),
			location.get("max_loot", 4)
		) * clampf(efficiency, 0.5, 1.8) * (1.0 + loot_bonus)
	)

	var items: Array = []
	for _i in range(count):
		var item = _roll_from_table(location.get("loot_table", []))
		if not item.is_empty():
			var inst = item.duplicate(true)
			inst["condition"] = randf_range(50.0, 95.0)
			_apply_quality(inst)
			items.append(inst)

	var ruble_base = randf_range(
		location.get("min_rubles", 0),
		location.get("max_rubles", 0)
	)

	return {
		"failed": false,
		"items": items,
		"rubles": roundi(ruble_base * efficiency),
		"danger_encountered": danger,
		"location_name": location.get("name", "Unknown"),
	}

func _apply_quality(item: Dictionary) -> void:
	if item.get("category", "") in ["weapon", "ammo"]:
		item["quality"] = "standard"
		item["loot_bonus"] = 0.0
		item["fail_reduction"] = 0.0
		return

	var roll := randf()
	var quality: String
	var eff_mult: float
	var loot_bonus: float = 0.0
	var fail_reduction: float = 0.0
	var value_mult: float

	if roll < 0.03:
		quality = "masterwork"; eff_mult = 1.5;  loot_bonus = 0.10; fail_reduction = 0.03; value_mult = 4.0
	elif roll < 0.15:
		quality = "pristine";   eff_mult = 1.3;  loot_bonus = 0.05; fail_reduction = 0.0;  value_mult = 1.8
	elif roll < 0.40:
		quality = "refined";    eff_mult = 1.15; loot_bonus = 0.0;  fail_reduction = 0.0;  value_mult = 1.2
	else:
		quality = "standard";   eff_mult = 1.0;  loot_bonus = 0.0;  fail_reduction = 0.0;  value_mult = 1.0

	item["quality"] = quality
	item["efficiency_bonus"] = item.get("efficiency_bonus", 0.0) * eff_mult
	item["loot_bonus"] = loot_bonus
	item["fail_reduction"] = fail_reduction
	item["base_value"] = roundi(item.get("base_value", 0) * value_mult)

func _roll_from_table(loot_table: Array) -> Dictionary:
	if loot_table.is_empty():
		return _random_item()
	var roll = randf()
	var cumulative = 0.0
	for entry in loot_table:
		cumulative += entry.get("weight", 0.1)
		if roll <= cumulative:
			return _find_item(entry.get("item_id", ""))
	return _random_item()

func _find_item(item_id: String) -> Dictionary:
	for item in _item_pool:
		if item.get("id", "") == item_id:
			return item
	return {}

func _random_item() -> Dictionary:
	if _item_pool.is_empty():
		return {}
	return _item_pool[randi() % _item_pool.size()]
