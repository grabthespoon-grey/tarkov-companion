extends Control

# ── Palette ───────────────────────────────────────────────────────────────
const C_BG      = Color(0.07, 0.07, 0.07)
const C_PANEL   = Color(0.11, 0.11, 0.11)
const C_BORDER  = Color(0.22, 0.18, 0.12)
const C_ACCENT  = Color(0.75, 0.55, 0.15)
const C_TEXT    = Color(0.85, 0.82, 0.75)
const C_DIM     = Color(0.45, 0.42, 0.35)
const C_RED     = Color(0.80, 0.15, 0.10)
const C_GREEN   = Color(0.20, 0.70, 0.25)

# ── UI References ──────────────────────────────────────────────────────────
var _status_label:   Label
var _level_label:    Label
var _rubles_label:   Label
var _efficiency_label: Label
var _deploy_btn:     Button
var _raid_panel:     PanelContainer
var _raid_progress:  ProgressBar
var _raid_label:     Label
var _raid_timer_label: Label
var _location_btns:  Array[Button] = []
var _equip_bars:     Dictionary = {}
var _inventory_list: VBoxContainer
var _selected_location: String = "factory"
var _gun_mod_panel:  Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_connect_signals()
	_refresh_all()

# ── Build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root = VBoxContainer.new()
	root.custom_minimum_size = Vector2(480, 0)
	root.add_theme_constant_override("separation", 4)
	scroll.add_child(root)

	_add_header(root)
	_add_operator_panel(root)
	_add_equipment_panel(root)
	_add_location_panel(root)
	_add_raid_panel(root)
	_add_inventory_panel(root)

	_gun_mod_panel = _build_gun_mod_panel()
	add_child(_gun_mod_panel)
	_gun_mod_panel.hide()

func _add_header(parent: Control) -> void:
	var hdr = _panel(parent, Color(0.05, 0.05, 0.05))
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hdr.add_child(hbox)

	var title = _label("⚔  TARKOV COMPANION", C_ACCENT, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)

	_rubles_label = _label("₽ 0", C_GREEN, 13)
	hbox.add_child(_rubles_label)

func _add_operator_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	p.add_child(vbox)

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	var name_lbl = _label("OPERATOR", C_ACCENT, 11)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	_level_label = _label("Lv.1", C_DIM, 11)
	hbox.add_child(_level_label)

	_status_label = _label("● READY", C_GREEN, 11)
	vbox.add_child(_status_label)

	_efficiency_label = _label("Efficiency: -- %", C_TEXT, 10)
	vbox.add_child(_efficiency_label)

func _add_equipment_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	p.add_child(vbox)
	vbox.add_child(_label("EQUIPMENT", C_ACCENT, 11))

	for slot in ["weapon", "armor", "helmet", "backpack"]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var lbl = _label(slot.to_upper(), C_DIM, 10)
		lbl.custom_minimum_size.x = 70
		row.add_child(lbl)

		var bar = ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = 0
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size.y = 16
		row.add_child(bar)

		var cond_lbl = _label("--", C_DIM, 10)
		cond_lbl.custom_minimum_size.x = 55
		row.add_child(cond_lbl)

		_equip_bars[slot] = {"bar": bar, "label": cond_lbl}

		if slot == "weapon":
			var mod_btn = _button("MOD", C_BORDER)
			mod_btn.custom_minimum_size.x = 40
			mod_btn.pressed.connect(_on_gun_mod_pressed)
			row.add_child(mod_btn)

func _add_location_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	p.add_child(vbox)
	vbox.add_child(_label("DEPLOY LOCATION", C_ACCENT, 11))

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox)

	for loc in LootSystem.get_all_locations():
		var btn = _button(loc.get("name", "?").split(" ")[0].to_upper(), C_PANEL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.set_meta("location_id", loc.get("id", ""))
		btn.pressed.connect(_on_location_selected.bind(loc.get("id", ""), btn))
		hbox.add_child(btn)
		_location_btns.append(btn)

	_deploy_btn = _button("▶  DEPLOY", C_ACCENT)
	_deploy_btn.pressed.connect(_on_deploy_pressed)
	vbox.add_child(_deploy_btn)

func _add_raid_panel(parent: Control) -> void:
	_raid_panel = PanelContainer.new()
	_raid_panel.add_theme_stylebox_override("panel", _make_stylebox(C_PANEL, C_BORDER))
	_raid_panel.hide()
	parent.add_child(_raid_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_raid_panel.add_child(vbox)

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)
	_raid_label = _label("RAID IN PROGRESS", C_ACCENT, 11)
	_raid_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_raid_label)
	_raid_timer_label = _label("--:--", C_TEXT, 11)
	hbox.add_child(_raid_timer_label)

	_raid_progress = ProgressBar.new()
	_raid_progress.min_value = 0.0
	_raid_progress.max_value = 1.0
	_raid_progress.value = 0.0
	_raid_progress.custom_minimum_size.y = 20
	vbox.add_child(_raid_progress)

func _add_inventory_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	p.add_child(vbox)
	vbox.add_child(_label("INVENTORY", C_ACCENT, 11))

	_inventory_list = VBoxContainer.new()
	_inventory_list.add_theme_constant_override("separation", 2)
	vbox.add_child(_inventory_list)

# ── Gun Mod Panel ──────────────────────────────────────────────────────────

func _build_gun_mod_panel() -> Control:
	var overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)

	var container = VBoxContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.custom_minimum_size = Vector2(440, 500)
	overlay.add_child(container)

	var hdr = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	container.add_child(hdr)
	var title = _label("GUN WORKSHOP", C_ACCENT, 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close_btn = _button("✕", C_RED)
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(func(): _gun_mod_panel.hide())
	hdr.add_child(close_btn)

	var body = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(body)

	# Left: weapon slots
	var slots_vbox = VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 6)
	slots_vbox.custom_minimum_size.x = 200
	body.add_child(slots_vbox)
	slots_vbox.set_meta("slots_container", true)

	# Right: stats
	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 4)
	body.add_child(stats_vbox)
	stats_vbox.set_meta("stats_container", true)

	return overlay

# ── Signal Handlers ────────────────────────────────────────────────────────

func _connect_signals() -> void:
	GameManager.operator_deployed.connect(_on_operator_deployed)
	GameManager.operator_returned.connect(_on_operator_returned)
	GameManager.equipment_changed.connect(func(_s): _refresh_equipment())
	GameManager.inventory_changed.connect(_refresh_inventory)
	GameManager.rubles_changed.connect(func(v): _rubles_label.text = "₽ %s" % _fmt_number(v))
	TimeManager.farm_progress_updated.connect(_on_farm_progress)

func _on_location_selected(loc_id: String, btn: Button) -> void:
	_selected_location = loc_id
	for b in _location_btns:
		b.add_theme_stylebox_override("normal", _make_stylebox(C_PANEL, C_BORDER))
	btn.add_theme_stylebox_override("normal", _make_stylebox(C_BORDER, C_ACCENT))

func _on_deploy_pressed() -> void:
	GameManager.deploy_operator(_selected_location)

func _on_operator_deployed(_loc_id: String) -> void:
	_deploy_btn.disabled = true
	_status_label.text = "● ON RAID"
	_status_label.add_theme_color_override("font_color", C_RED)
	_raid_panel.show()
	var loc = LootSystem.get_location(_selected_location)
	_raid_label.text = "RAID: %s" % loc.get("name", "Unknown").to_upper()

func _on_operator_returned(_result: Dictionary) -> void:
	_deploy_btn.disabled = false
	_status_label.text = "● READY"
	_status_label.add_theme_color_override("font_color", C_GREEN)
	_raid_panel.hide()
	_raid_progress.value = 0.0
	_refresh_equipment()

func _on_farm_progress(progress: float, time_remaining: int) -> void:
	_raid_progress.value = progress
	var mins: int = floori(time_remaining / 60.0)
	var secs: int = time_remaining % 60
	_raid_timer_label.text = "%02d:%02d" % [mins, secs]

func _on_gun_mod_pressed() -> void:
	_refresh_gun_mod_panel()
	_gun_mod_panel.show()

# ── Refresh ────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	var state = GameManager.game_state
	_level_label.text = "Lv.%d" % state.operator.level
	_rubles_label.text = "₽ %s" % _fmt_number(state.rubles)
	_refresh_equipment()
	_refresh_inventory()

func _refresh_equipment() -> void:
	var equip = GameManager.game_state.equipment
	for slot in _equip_bars:
		var item = equip.get(slot)
		var bar: ProgressBar = _equip_bars[slot]["bar"]
		var lbl: Label = _equip_bars[slot]["label"]
		if item == null:
			bar.value = 0
			lbl.text = "EMPTY"
			lbl.add_theme_color_override("font_color", C_DIM)
		else:
			var cond = item.get("condition", 100.0)
			bar.value = cond
			lbl.text = EquipmentSystem.get_condition_label(cond)
			lbl.add_theme_color_override("font_color", EquipmentSystem.get_condition_color(cond))

	var eff = GameManager.get_farming_efficiency()
	_efficiency_label.text = "Efficiency: %.0f%%" % (eff * 100.0)

func _refresh_inventory() -> void:
	for child in _inventory_list.get_children():
		child.queue_free()

	var inventory = GameManager.game_state.inventory
	if inventory.is_empty():
		_inventory_list.add_child(_label("No items", C_DIM, 10))
		return

	for item in inventory:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_inventory_list.add_child(row)

		var name_lbl = _label(item.get("name", "Unknown"), C_TEXT, 10)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var rarity_color = _rarity_color(item.get("rarity", "common"))
		var rarity_lbl = _label(item.get("rarity", "").to_upper(), rarity_color, 9)
		row.add_child(rarity_lbl)

		var sell_btn = _button("SELL", C_PANEL)
		sell_btn.custom_minimum_size = Vector2(42, 20)
		sell_btn.pressed.connect(GameManager.sell_item.bind(item))
		row.add_child(sell_btn)

		if item.get("steam_tradeable", false):
			var trade_btn = _button("TRADE", C_BORDER)
			trade_btn.custom_minimum_size = Vector2(48, 20)
			trade_btn.pressed.connect(SteamManager.open_market_listing.bind(item.get("steam_item_def", 0)))
			row.add_child(trade_btn)

func _refresh_gun_mod_panel() -> void:
	var overlay: Control = _gun_mod_panel
	var container = overlay.get_child(0)
	var body: HSplitContainer = container.get_child(1)

	var slots_vbox: VBoxContainer = body.get_child(0)
	var stats_vbox: VBoxContainer = body.get_child(1)

	for c in slots_vbox.get_children(): c.queue_free()
	for c in stats_vbox.get_children(): c.queue_free()

	var weapon = GameManager.game_state.equipment.get("weapon")
	if weapon == null:
		slots_vbox.add_child(_label("No weapon equipped", C_DIM, 10))
		return

	slots_vbox.add_child(_label(weapon.get("name", "?").to_upper(), C_ACCENT, 11))

	for slot in GunModSystem.get_available_slots(weapon):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		slots_vbox.add_child(row)

		var slot_lbl = _label(slot.to_upper().replace("_", " "), C_DIM, 9)
		slot_lbl.custom_minimum_size.x = 80
		row.add_child(slot_lbl)

		var mods = weapon.get("mods", {})
		if slot in mods:
			var mod_name = _label(mods[slot].get("name", "?"), C_TEXT, 9)
			mod_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(mod_name)
			var det_btn = _button("✕", C_RED)
			det_btn.custom_minimum_size = Vector2(22, 22)
			det_btn.pressed.connect(func():
				GunModSystem.detach_mod(weapon, slot)
				_refresh_gun_mod_panel()
				_refresh_inventory()
				_refresh_equipment()
			)
			row.add_child(det_btn)
		else:
			var empty_lbl = _label("[ empty ]", C_DIM, 9)
			empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(empty_lbl)

	# Available compatible mods
	slots_vbox.add_child(_label("AVAILABLE MODS", C_ACCENT, 10))
	var compatible = GunModSystem.get_compatible_mods(weapon, GameManager.game_state.inventory)
	if compatible.is_empty():
		slots_vbox.add_child(_label("No compatible mods in inventory", C_DIM, 9))
	for mod in compatible:
		var row = HBoxContainer.new()
		slots_vbox.add_child(row)
		var n = _label(mod.get("name", "?"), C_TEXT, 9)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var att_btn = _button("ATTACH", C_GREEN)
		att_btn.custom_minimum_size = Vector2(55, 22)
		att_btn.pressed.connect(func():
			GunModSystem.attach_mod(weapon, mod)
			_refresh_gun_mod_panel()
			_refresh_inventory()
			_refresh_equipment()
		)
		row.add_child(att_btn)

	# Stats
	stats_vbox.add_child(_label("STATS", C_ACCENT, 11))
	var stats = GunModSystem.calculate_weapon_stats(weapon)
	var stat_order = ["damage", "accuracy", "ergonomics", "recoil_vertical", "recoil_horizontal", "fire_rate"]
	for stat in stat_order:
		if stat in stats:
			var row = HBoxContainer.new()
			stats_vbox.add_child(row)
			var k = _label(stat.replace("_", " ").to_upper(), C_DIM, 9)
			k.custom_minimum_size.x = 90
			row.add_child(k)
			row.add_child(_label(str(stats[stat]), C_TEXT, 9))

# ── UI Helpers ─────────────────────────────────────────────────────────────

func _panel(parent: Control, bg_color: Color = C_PANEL) -> PanelContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _make_stylebox(bg_color, C_BORDER))
	parent.add_child(p)
	return p

func _label(text: String, color: Color, font_size: int) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	return l

func _button(text: String, bg: Color) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", _make_stylebox(bg, C_BORDER))
	b.add_theme_stylebox_override("hover",  _make_stylebox(bg.lightened(0.15), C_ACCENT))
	b.add_theme_stylebox_override("pressed", _make_stylebox(bg.darkened(0.2), C_ACCENT))
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_font_size_override("font_size", 10)
	return b

func _make_stylebox(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	s.corner_radius_top_left = 2
	s.corner_radius_top_right = 2
	s.corner_radius_bottom_left = 2
	s.corner_radius_bottom_right = 2
	return s

func _rarity_color(rarity: String) -> Color:
	match rarity:
		"common":   return Color(0.6, 0.6, 0.6)
		"uncommon": return Color(0.3, 0.7, 0.3)
		"rare":     return Color(0.3, 0.5, 0.9)
		"epic":     return Color(0.7, 0.3, 0.9)
		_:          return C_DIM

func _fmt_number(n: int) -> String:
	if n >= 1000000: return "%.1fM" % (n / 1000000.0)
	if n >= 1000:    return "%.1fk" % (n / 1000.0)
	return str(n)
