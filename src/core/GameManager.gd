extends Node

signal operator_deployed(location_id: String)
signal operator_returned(loot_result: Dictionary)
signal equipment_changed(slot: String)
signal inventory_changed()
signal rubles_changed(new_amount: int)

var game_state: Dictionary = {
	"operator": {
		"name": "Operator",
		"level": 1,
		"experience": 0,
		"is_deployed": false,
		"deploy_start_time": 0.0,
		"deploy_location": "",
		"ammo_penalty": 0.0,
	},
	"ammo": {
		"9mm":    90,
		"7.62mm": 60,
		"5.56mm": 45,
	},
	"equipment": {
		"weapon": {
			"type_id": "mp5",
			"name": "MP5",
			"condition": 100.0,
			"mods": {},
		},
	},
	"inventory": [],
	"rubles": 5000,
	"total_raids": 0,
	"successful_raids": 0,
}

func _ready() -> void:
	TimeManager.farm_completed.connect(_on_farm_completed)
	# Deferred so all autoload _ready() calls finish before LootSystem data is needed
	call_deferred("_load_save")

func _load_save() -> void:
	SaveManager.load_game()
	# Migrate saves that predate the ammo system
	if "ammo" not in game_state:
		game_state["ammo"] = {"9mm": 90, "7.62mm": 60, "5.56mm": 45}
	if "ammo_penalty" not in game_state.operator:
		game_state.operator["ammo_penalty"] = 0.0

func get_farming_efficiency() -> float:
	return EquipmentSystem.calculate_efficiency(game_state.equipment)

func deploy_operator(location_id: String) -> bool:
	if game_state.operator.is_deployed:
		return false

	var weapon = game_state.equipment.get("weapon")
	var weapon_id: String = weapon.get("type_id", "") if weapon is Dictionary else ""
	if not AmmoSystem.can_deploy(weapon_id):
		return false

	var penalty := AmmoSystem.get_fail_penalty(weapon_id)
	AmmoSystem.consume_for_raid(weapon_id)
	game_state.operator.ammo_penalty = penalty
	game_state.operator.is_deployed = true
	game_state.operator.deploy_start_time = Time.get_unix_time_from_system()
	game_state.operator.deploy_location = location_id

	TimeManager.start_farm_timer(location_id, get_farming_efficiency())
	emit_signal("operator_deployed", location_id)
	SaveManager.save_game()
	return true

func _on_farm_completed(location_id: String, efficiency: float) -> void:
	var loot_result = LootSystem.roll_loot(location_id, efficiency, game_state.operator.get("ammo_penalty", 0.0))

	game_state.operator.is_deployed = false
	game_state.operator.deploy_location = ""
	game_state.total_raids += 1

	if not loot_result.get("failed", false):
		game_state.successful_raids += 1
		for item in loot_result.get("items", []):
			game_state.inventory.append(item.duplicate())
		game_state.rubles += loot_result.get("rubles", 0)
		emit_signal("inventory_changed")
		emit_signal("rubles_changed", game_state.rubles)

	EquipmentSystem.degrade_equipment_after_raid(
		game_state.equipment,
		loot_result.get("danger_encountered", 0.5)
	)

	_add_experience(loot_result)
	emit_signal("operator_returned", loot_result)
	SaveManager.save_game()

func _add_experience(loot_result: Dictionary) -> void:
	if loot_result.get("failed", false):
		return
	var xp_gain = 100 + loot_result.get("items", []).size() * 25
	game_state.operator.experience += xp_gain
	var xp_needed = game_state.operator.level * 500
	if game_state.operator.experience >= xp_needed:
		game_state.operator.level += 1
		game_state.operator.experience -= xp_needed

func equip_item(item: Dictionary, slot: String) -> bool:
	if slot not in game_state.equipment:
		return false
	var current = game_state.equipment[slot]
	if current != null:
		game_state.inventory.append(current)
	game_state.equipment[slot] = item
	game_state.inventory.erase(item)
	emit_signal("equipment_changed", slot)
	emit_signal("inventory_changed")
	SaveManager.save_game()
	return true

func unequip_item(slot: String) -> bool:
	if slot not in game_state.equipment or game_state.equipment[slot] == null:
		return false
	game_state.inventory.append(game_state.equipment[slot])
	game_state.equipment[slot] = null
	emit_signal("equipment_changed", slot)
	emit_signal("inventory_changed")
	SaveManager.save_game()
	return true

func sell_item(item: Dictionary) -> bool:
	if not game_state.inventory.has(item):
		return false
	game_state.inventory.erase(item)
	game_state.rubles += item.get("base_value", 100)
	emit_signal("inventory_changed")
	emit_signal("rubles_changed", game_state.rubles)
	SaveManager.save_game()
	return true
