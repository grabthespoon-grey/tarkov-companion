extends Node

const WEIGHT_WEAPON = 0.50
const WEIGHT_ARMOR  = 0.30
const WEIGHT_MISC   = 0.20
const DEGRADE_BASE  = 0.04  # 4% per raid at zero danger

func calculate_efficiency(equipment: Dictionary) -> float:
	var weapon_cond = _slot_condition(equipment.get("weapon"))
	var armor_cond  = _slot_condition(equipment.get("armor"))
	var misc_cond = (
		_slot_condition(equipment.get("helmet")) +
		_slot_condition(equipment.get("backpack"))
	) / 2.0

	var base = (
		weapon_cond * WEIGHT_WEAPON +
		armor_cond  * WEIGHT_ARMOR  +
		misc_cond   * WEIGHT_MISC
	)

	var mod_bonus = GunModSystem.calculate_efficiency_bonus(equipment.get("weapon"))
	return clampf(base + mod_bonus, 0.05, 2.0)

func degrade_equipment_after_raid(equipment: Dictionary, danger_factor: float) -> void:
	var deg = DEGRADE_BASE * (1.0 + danger_factor)
	for slot in equipment:
		var item = equipment[slot]
		if item != null:
			item["condition"] = maxf(0.0, item.get("condition", 100.0) - deg * 100.0)

func repair_item(item: Dictionary, amount: float) -> void:
	item["condition"] = minf(100.0, item.get("condition", 100.0) + amount)

func get_condition_label(condition: float) -> String:
	if condition >= 80.0: return "PERFECT"
	if condition >= 60.0: return "GOOD"
	if condition >= 40.0: return "WORN"
	if condition >= 20.0: return "DAMAGED"
	return "CRITICAL"

func get_condition_color(condition: float) -> Color:
	if condition >= 80.0: return Color(0.2, 0.8, 0.2)
	if condition >= 60.0: return Color(0.6, 0.8, 0.2)
	if condition >= 40.0: return Color(0.9, 0.7, 0.1)
	if condition >= 20.0: return Color(0.9, 0.4, 0.1)
	return Color(0.9, 0.1, 0.1)

func _slot_condition(item) -> float:
	if item == null:
		return 0.3
	return item.get("condition", 100.0) / 100.0
