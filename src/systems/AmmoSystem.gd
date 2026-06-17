extends Node

signal ammo_changed(ammo_type: String, new_count: int)

const AMMO_CONFIG: Dictionary = {
	"9mm": {
		"name":             "9x19mm Parabellum",
		"weapon_id":        "mp5",
		"buy_cost_per_30":  1500,
		"regen_per_sec":    0.3333,  # 1 round / 3 sec → full 90 in 4.5 min
		"regen_cap":        90,
		"min_for_raid":     30,
		"optimal":          90,
		"consume_per_raid": 30,
	},
	"7.62mm": {
		"name":             "7.62x39mm",
		"weapon_id":        "ak74",
		"buy_cost_per_30":  4200,
		"regen_per_sec":    0.3333,  # 1 round / 3 sec → full 90 in 4.5 min
		"regen_cap":        90,
		"min_for_raid":     30,
		"optimal":          90,
		"consume_per_raid": 30,
	},
	"5.56mm": {
		"name":             "5.56x45mm NATO",
		"weapon_id":        "m4a1",
		"buy_cost_per_30":  9000,
		"regen_per_sec":    0.3333,  # 1 round / 3 sec → full 90 in 4.5 min
		"regen_cap":        90,
		"min_for_raid":     30,
		"optimal":          90,
		"consume_per_raid": 30,
	},
}

var _regen_accum: Dictionary = {"9mm": 0.0, "7.62mm": 0.0, "5.56mm": 0.0}

func get_ammo_type_for_weapon(weapon_id: String) -> String:
	for ammo_type in AMMO_CONFIG:
		if AMMO_CONFIG[ammo_type]["weapon_id"] == weapon_id:
			return ammo_type
	return ""

func get_count(ammo_type: String) -> int:
	return GameManager.game_state.get("ammo", {}).get(ammo_type, 0)

func can_deploy(weapon_id: String) -> bool:
	var ammo_type := get_ammo_type_for_weapon(weapon_id)
	if ammo_type.is_empty():
		return false
	return get_count(ammo_type) >= AMMO_CONFIG[ammo_type]["min_for_raid"]

# Returns 0.0–0.2 additional fail chance based on how low ammo is
func get_fail_penalty(weapon_id: String) -> float:
	var ammo_type := get_ammo_type_for_weapon(weapon_id)
	if ammo_type.is_empty():
		return 0.0
	var cfg = AMMO_CONFIG[ammo_type]
	var ratio := float(get_count(ammo_type)) / float(cfg["optimal"])
	return clampf((1.0 - ratio) * 0.2, 0.0, 0.2)

func consume_for_raid(weapon_id: String) -> void:
	var ammo_type := get_ammo_type_for_weapon(weapon_id)
	if ammo_type.is_empty():
		return
	var ammo: Dictionary = GameManager.game_state.get("ammo", {})
	var new_count := maxi(0, ammo.get(ammo_type, 0) - AMMO_CONFIG[ammo_type]["consume_per_raid"])
	ammo[ammo_type] = new_count
	emit_signal("ammo_changed", ammo_type, new_count)

func buy_ammo(ammo_type: String) -> bool:
	if ammo_type not in AMMO_CONFIG:
		return false
	var cfg = AMMO_CONFIG[ammo_type]
	if GameManager.game_state.rubles < cfg["buy_cost_per_30"]:
		return false
	GameManager.game_state.rubles -= cfg["buy_cost_per_30"]
	var ammo: Dictionary = GameManager.game_state.get("ammo", {})
	var new_count: int = int(ammo.get(ammo_type, 0)) + 30
	ammo[ammo_type] = new_count
	emit_signal("ammo_changed", ammo_type, new_count)
	GameManager.rubles_changed.emit(GameManager.game_state.rubles)
	SaveManager.save_game()
	return true

func tick(delta: float) -> void:
	var ammo: Dictionary = GameManager.game_state.get("ammo", {})
	for ammo_type in AMMO_CONFIG:
		var cfg = AMMO_CONFIG[ammo_type]
		var current: int = ammo.get(ammo_type, 0)
		if current >= cfg["regen_cap"]:
			continue
		_regen_accum[ammo_type] += cfg["regen_per_sec"] * delta
		if _regen_accum[ammo_type] >= 1.0:
			var add := int(_regen_accum[ammo_type])
			_regen_accum[ammo_type] -= float(add)
			var new_count := mini(current + add, cfg["regen_cap"])
			ammo[ammo_type] = new_count
			emit_signal("ammo_changed", ammo_type, new_count)
