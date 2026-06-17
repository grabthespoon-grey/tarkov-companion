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

const PHASE_LABELS:  Array = ["침투", "탐색", "교전", "루팅", "탈출"]
const PHASE_DETAILS: Array = ["경계선 돌파 중...", "루팅 포인트 탐색 중...", "적 세력과 교전 중", "아이템 회수 중...", "탈출구로 이동 중..."]
const PHASE_COLORS:  Array = [Color(0.45, 0.42, 0.35), Color(0.85, 0.82, 0.75), Color(0.80, 0.15, 0.10), Color(0.20, 0.70, 0.25), Color(0.75, 0.55, 0.15)]
const EVENT_POOL: Dictionary = {
	"factory": ["스캐브 1명 제거", "발소리 감지 — 동쪽", "기계실 진입", "연기 감지", "적 2명 교전", "창고 A 루팅", "공장 남쪽 구역 진입", "금속 파편 수거"],
	"customs": ["PMC 흔적 발견", "트럭 주변 수색", "세관 건물 진입", "지붕 저격수 포착", "적 2명 교전 — 제압", "컨테이너 야드 진입", "전파 방해 감지", "탈출 경로 확인"],
	"woods":   ["수풀 사이 이동", "야영지 흔적 발견", "저격 위협 — 엄폐", "군사 캐시 발견", "안개로 시야 제한", "군사 시설 진입", "드론 소리 감지", "지뢰 우회 탐색"],
	"lab":     ["보안 게이트 우회", "실험실 구역 진입", "이상 생명체 감지", "전력 차단 구역", "레드 카드 사용", "보안 시스템 교란", "연구 데이터 회수", "냉동 보관실 진입"],
}

# ── UI References ──────────────────────────────────────────────────────────
var _status_label:      Label
var _level_label:       Label
var _rubles_label:      Label
var _efficiency_label:  Label
var _deploy_btn:        Button
var _raid_panel:        PanelContainer
var _raid_progress:     ProgressBar
var _raid_label:        Label
var _raid_timer_label:  Label
var _location_btns:     Array[Button] = []
var _equip_bars:        Dictionary = {}
var _inventory_list:    VBoxContainer
var _selected_location: String = "factory"
var _gun_mod_panel:       Control
var _gun_mod_slots_vbox:  VBoxContainer
var _gun_mod_stats_vbox:  VBoxContainer
var _ammo_vbox:           VBoxContainer
var _raid_phase_label:    Label
var _raid_phase_detail:   Label
var _raid_log_vbox:       VBoxContainer
var _log_tick:            int = 0
var _log_entries:         Array = []
var _raid_location_id:    String = ""
var _result_panel:        Control
var _result_items_vbox:   VBoxContainer
var _pending_items:       Array = []
var _current_loot_result: Dictionary = {}
var _result_popup_visible: bool = false
var _market_panel:        Control
var _market_content_vbox: VBoxContainer
var _market_refresh_label: Label
var _market_tab:          String = "browse"
var _market_browse_btn:   Button
var _market_listings_btn: Button
var _market_tick_timer:   Timer
var _list_dialog:         Control
var _list_dialog_item:    Dictionary = {}
var _list_dialog_spin:    SpinBox
var _list_dialog_fee_lbl: Label
var _list_dialog_name_lbl: Label
var _list_dialog_mkt_lbl: Label
var _market_dyn:          Array = []   # [{lbl, data, kind}] live countdown labels

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
	_add_ammo_panel(root)
	_add_location_panel(root)
	_add_raid_panel(root)
	_add_inventory_panel(root)

	# Overlays live outside the scroll container so they cover everything
	_gun_mod_panel = _build_gun_mod_panel()
	add_child(_gun_mod_panel)
	_gun_mod_panel.hide()

	_result_panel = _build_result_panel()
	add_child(_result_panel)
	_result_panel.hide()

	_market_panel = _build_market_panel()
	add_child(_market_panel)
	_market_panel.hide()

	_list_dialog = _build_list_dialog()
	add_child(_list_dialog)
	_list_dialog.hide()

	# Drives live countdowns (refresh timer, listing sale ETA) while market open.
	_market_tick_timer = Timer.new()
	_market_tick_timer.wait_time = 1.0
	_market_tick_timer.timeout.connect(_on_market_tick)
	add_child(_market_tick_timer)
	_market_tick_timer.start()

func _add_header(parent: Control) -> void:
	var hdr = _panel(parent, Color(0.05, 0.05, 0.05))
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hdr.add_child(hbox)

	var title = _label("⚔  TARKOV COMPANION", C_ACCENT, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)

	var market_btn = _button("☰ MARKET", C_BORDER)
	market_btn.custom_minimum_size = Vector2(80, 24)
	market_btn.pressed.connect(_on_market_pressed)
	hbox.add_child(market_btn)

	_rubles_label = _label("₽ 0", C_GREEN, 13)
	hbox.add_child(_rubles_label)

func _add_operator_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
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

	var weapon_row = HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 8)
	vbox.add_child(weapon_row)

	weapon_row.add_child(_label("WEAPON", C_DIM, 10))

	var weapon_name_lbl = _label("--", C_TEXT, 10)
	weapon_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_row.add_child(weapon_name_lbl)
	# Condition bar removed — restore by adding ProgressBar + condition label here
	_equip_bars["weapon"] = {"name_lbl": weapon_name_lbl}

	var mod_btn = _button("MOD", C_BORDER)
	mod_btn.custom_minimum_size.x = 40
	mod_btn.pressed.connect(_on_gun_mod_pressed)
	weapon_row.add_child(mod_btn)

func _add_ammo_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	p.add_child(vbox)
	vbox.add_child(_label("AMMO", C_ACCENT, 11))
	_ammo_vbox = VBoxContainer.new()
	_ammo_vbox.add_theme_constant_override("separation", 3)
	vbox.add_child(_ammo_vbox)

func _add_location_panel(parent: Control) -> void:
	var p = _panel(parent)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	p.add_child(vbox)
	vbox.add_child(_label("DEPLOY LOCATION", C_ACCENT, 11))

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(hbox)

	var first_btn: Button = null
	for loc in LootSystem.get_all_locations():
		var loc_id: String = loc.get("id", "")
		var btn = _button(loc.get("name", "?").split(" ")[0].to_upper(), C_PANEL)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.set_meta("location_id", loc_id)
		btn.pressed.connect(_on_location_selected.bind(loc_id, btn))
		hbox.add_child(btn)
		_location_btns.append(btn)
		if first_btn == null:
			first_btn = btn

	# Highlight the default selected location on startup
	if first_btn != null:
		first_btn.add_theme_stylebox_override("normal", _make_stylebox(C_BORDER, C_ACCENT))

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
	_raid_progress.show_percentage = false
	_raid_progress.custom_minimum_size.y = 20
	vbox.add_child(_raid_progress)

	var phase_row = HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 10)
	vbox.add_child(phase_row)

	_raid_phase_label = _label("침투", C_DIM, 13)
	_raid_phase_label.custom_minimum_size.x = 40
	phase_row.add_child(_raid_phase_label)

	_raid_phase_detail = _label("경계선 돌파 중...", C_DIM, 9)
	_raid_phase_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phase_row.add_child(_raid_phase_detail)

	_raid_log_vbox = VBoxContainer.new()
	_raid_log_vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(_raid_log_vbox)

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
	# Dark overlay — clicking it closes the panel
	var overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_gun_mod_panel.hide()
	)

	# CenterContainer positions the inner panel without PRESET_CENTER quirks
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	# Dialog panel — MOUSE_FILTER_STOP prevents clicks from reaching the overlay
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 460)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_stylebox(C_PANEL, C_BORDER))
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hdr = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)

	var title = _label("GUN WORKSHOP", C_ACCENT, 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)

	var hint = _label("ESC / click outside to close", C_DIM, 9)
	hdr.add_child(hint)

	var close_btn = _button("✕", C_RED)
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(func(): _gun_mod_panel.hide())
	hdr.add_child(close_btn)

	var body = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	_gun_mod_slots_vbox = VBoxContainer.new()
	_gun_mod_slots_vbox.add_theme_constant_override("separation", 6)
	_gun_mod_slots_vbox.custom_minimum_size.x = 220
	body.add_child(_gun_mod_slots_vbox)

	_gun_mod_stats_vbox = VBoxContainer.new()
	_gun_mod_stats_vbox.add_theme_constant_override("separation", 4)
	body.add_child(_gun_mod_stats_vbox)

	return overlay

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Close the topmost open overlay (dialog before its parent panel).
	if _list_dialog.visible:
		_list_dialog.hide()
		get_viewport().set_input_as_handled()
	elif _market_panel.visible:
		_market_panel.hide()
		get_viewport().set_input_as_handled()
	elif _gun_mod_panel.visible:
		_gun_mod_panel.hide()
		get_viewport().set_input_as_handled()

# ── Signal Handlers ────────────────────────────────────────────────────────

func _connect_signals() -> void:
	GameManager.operator_deployed.connect(_on_operator_deployed)
	GameManager.operator_returned.connect(_on_operator_returned)
	GameManager.raid_result_pending.connect(_on_raid_result_pending)
	GameManager.equipment_changed.connect(func(_s): _refresh_equipment())
	GameManager.equipment_changed.connect(func(_s): _refresh_ammo_panel())
	GameManager.inventory_changed.connect(_refresh_inventory)
	GameManager.rubles_changed.connect(func(v): _rubles_label.text = "₽ %s" % _fmt_number(v))
	GameManager.rubles_changed.connect(func(_v): _refresh_ammo_panel())
	TimeManager.farm_progress_updated.connect(_on_farm_progress)
	AmmoSystem.ammo_changed.connect(func(_t, _c): _refresh_ammo_panel())
	MarketSystem.market_refreshed.connect(_on_market_changed)
	MarketSystem.listings_changed.connect(_on_market_changed)
	MarketSystem.listing_sold.connect(_on_listing_sold)

func _on_location_selected(loc_id: String, btn: Button) -> void:
	_selected_location = loc_id
	for b in _location_btns:
		b.add_theme_stylebox_override("normal", _make_stylebox(C_PANEL, C_BORDER))
	btn.add_theme_stylebox_override("normal", _make_stylebox(C_BORDER, C_ACCENT))

func _on_deploy_pressed() -> void:
	GameManager.deploy_operator(_selected_location)

func _on_operator_deployed(loc_id: String) -> void:
	_deploy_btn.disabled = true
	_status_label.text = "● ON RAID"
	_status_label.add_theme_color_override("font_color", C_RED)
	_raid_panel.show()
	var loc = LootSystem.get_location(loc_id)
	_raid_label.text = "RAID: %s" % loc.get("name", "Unknown").to_upper()
	_raid_location_id = loc_id
	_log_tick = 0
	_log_entries.clear()
	for c in _raid_log_vbox.get_children(): c.queue_free()
	_raid_phase_label.text = PHASE_LABELS[0]
	_raid_phase_label.add_theme_color_override("font_color", PHASE_COLORS[0])
	_raid_phase_detail.text = PHASE_DETAILS[0]
	_raid_phase_detail.add_theme_color_override("font_color", C_DIM)

func _on_operator_returned(_result: Dictionary) -> void:
	_status_label.text = "● READY"
	_status_label.add_theme_color_override("font_color", C_GREEN)
	_raid_panel.hide()
	_raid_progress.value = 0.0
	_log_entries.clear()
	var state = GameManager.game_state
	_level_label.text = "Lv.%d" % state.operator.level
	_refresh_equipment()
	_refresh_ammo_panel()

func _on_farm_progress(progress: float, time_remaining: int) -> void:
	_raid_progress.value = progress
	var mins: int = floori(time_remaining / 60.0)
	var secs: int = time_remaining % 60
	_raid_timer_label.text = "%02d:%02d" % [mins, secs]

	var phase := _get_phase_index(progress)
	_raid_phase_label.text = PHASE_LABELS[phase]
	_raid_phase_label.add_theme_color_override("font_color", PHASE_COLORS[phase])
	_raid_phase_detail.text = PHASE_DETAILS[phase]

	_log_tick += 1
	if _log_tick % 3 == 0:
		_append_log_entry()

func _on_gun_mod_pressed() -> void:
	_refresh_gun_mod_panel()
	_gun_mod_panel.show()

func _on_raid_result_pending(loot_result: Dictionary) -> void:
	_raid_panel.hide()
	_raid_progress.value = 0.0
	_log_entries.clear()
	_result_popup_visible = true
	_deploy_btn.disabled = true
	_current_loot_result = loot_result
	_pending_items = loot_result.get("pending_items", []).duplicate()
	_refresh_result_panel()
	_result_panel.show()

func _refresh_result_panel() -> void:
	for c in _result_items_vbox.get_children(): c.queue_free()

	var failed: bool = _current_loot_result.get("failed", false)
	var loc_name: String = _current_loot_result.get("location_name", "Unknown")
	var ammo_type: String = _current_loot_result.get("ammo_type", "")
	var ammo_consumed: int = _current_loot_result.get("ammo_consumed", 30)

	var hdr = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	_result_items_vbox.add_child(hdr)
	var status_lbl = _label("FAILED" if failed else "SUCCESS", C_RED if failed else C_GREEN, 12)
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(status_lbl)
	hdr.add_child(_label(loc_name, C_DIM, 10))

	if not ammo_type.is_empty():
		_result_items_vbox.add_child(_label("탄약 소모: %s × %d발" % [ammo_type, ammo_consumed], C_DIM, 9))

	if not failed:
		var rubles: int = _current_loot_result.get("rubles", 0)
		if rubles > 0:
			_result_items_vbox.add_child(_label("₽ +%s" % _fmt_number(rubles), C_GREEN, 10))

		_result_items_vbox.add_child(HSeparator.new())

		if _pending_items.is_empty():
			_result_items_vbox.add_child(_label("획득 아이템 없음", C_DIM, 10))
		else:
			_result_items_vbox.add_child(_label("획득 아이템 (%d)  — 판매하지 않으면 인벤토리 보관" % _pending_items.size(), C_DIM, 9))
			for item in _pending_items:
				var captured_item = item
				var row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				_result_items_vbox.add_child(row)

				var name_lbl = _label(item.get("name", "?"), C_TEXT, 10)
				name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(name_lbl)

				var tier: int = item.get("tier", 0)
				if tier >= 1 and item.get("category", "") != "weapon":
					row.add_child(_label("T%d" % tier, _tier_color(tier), 9))
					var ql := _quality_label(item.get("quality", "standard"))
					if not ql.is_empty():
						row.add_child(_label(ql, _quality_color(item.get("quality", "standard")), 9))
				else:
					row.add_child(_label(item.get("rarity", "").to_upper(), _rarity_color(item.get("rarity", "common")), 9))

				var sell_value: int = item.get("base_value", 100)
				var sell_btn = _button("SELL ₽%s" % _fmt_number(sell_value), C_PANEL)
				sell_btn.custom_minimum_size = Vector2(80, 22)
				sell_btn.pressed.connect(func(): _on_result_sell_item(captured_item))
				row.add_child(sell_btn)

func _on_result_sell_item(item: Dictionary) -> void:
	_pending_items.erase(item)
	GameManager.sell_pending_item(item)
	_refresh_result_panel()

func _on_result_confirm() -> void:
	_result_popup_visible = false
	_result_panel.hide()
	GameManager.confirm_loot(_pending_items)
	_pending_items.clear()

func _build_result_panel() -> Control:
	var overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_stylebox(C_PANEL, C_BORDER))
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(_label("RAID RESULT", C_ACCENT, 13))

	_result_items_vbox = VBoxContainer.new()
	_result_items_vbox.add_theme_constant_override("separation", 5)
	vbox.add_child(_result_items_vbox)

	var confirm_btn = _button("✔  CONFIRM", C_ACCENT)
	confirm_btn.pressed.connect(_on_result_confirm)
	vbox.add_child(confirm_btn)

	return overlay

func _get_phase_index(progress: float) -> int:
	if progress < 0.2:  return 0
	if progress < 0.4:  return 1
	if progress < 0.65: return 2
	if progress < 0.85: return 3
	return 4

func _append_log_entry() -> void:
	var pool: Array = EVENT_POOL.get(_raid_location_id, [])
	if pool.is_empty():
		return
	var text: String = pool[randi() % pool.size()]
	_log_entries.insert(0, "[T+%02ds] %s" % [_log_tick, text])
	if _log_entries.size() > 4:
		_log_entries.resize(4)
	for c in _raid_log_vbox.get_children(): c.queue_free()
	for i in _log_entries.size():
		_raid_log_vbox.add_child(_label(_log_entries[i], C_TEXT if i == 0 else C_DIM, 9))

# ── Refresh ────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	var state = GameManager.game_state
	_level_label.text = "Lv.%d" % state.operator.level
	_rubles_label.text = "₽ %s" % _fmt_number(state.rubles)
	_refresh_equipment()
	_refresh_ammo_panel()
	_refresh_inventory()

func _refresh_equipment() -> void:
	var weapon = GameManager.game_state.equipment.get("weapon")
	var name_lbl: Label = _equip_bars["weapon"]["name_lbl"]
	# Condition display removed — restore by reading weapon.get("condition") here
	if weapon == null:
		name_lbl.text = "EMPTY"
		name_lbl.add_theme_color_override("font_color", C_DIM)
	else:
		name_lbl.text = weapon.get("name", "Unknown")
		name_lbl.add_theme_color_override("font_color", C_TEXT)

	var eff := GameManager.get_farming_efficiency()
	_efficiency_label.text = "Efficiency: %.0f%%" % (eff * 100.0)

func _refresh_ammo_panel() -> void:
	for c in _ammo_vbox.get_children(): c.queue_free()

	var weapon = GameManager.game_state.equipment.get("weapon")
	var weapon_id: String = weapon.get("type_id", "") if weapon is Dictionary else ""
	var ammo_type := AmmoSystem.get_ammo_type_for_weapon(weapon_id)
	if ammo_type.is_empty():
		_ammo_vbox.add_child(_label("No weapon equipped", C_DIM, 9))
		_deploy_btn.disabled = GameManager.game_state.operator.is_deployed
		return

	var cfg = AmmoSystem.AMMO_CONFIG[ammo_type]
	var count := AmmoSystem.get_count(ammo_type)
	var cap: int = cfg["regen_cap"]
	var min_raid: int = cfg["min_for_raid"]
	var optimal: int = cfg["optimal"]

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_ammo_vbox.add_child(row)

	var count_color := C_GREEN if count >= optimal else (C_ACCENT if count >= min_raid else C_RED)
	var type_lbl = _label("%s  %d/%d" % [ammo_type, count, cap], count_color, 10)
	type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(type_lbl)

	var regen_per_min := int(cfg["regen_per_sec"] * 60.0 + 0.5)
	row.add_child(_label("+%d/min" % regen_per_min, C_DIM, 9))

	var captured_ammo_type := ammo_type
	var buy_btn = _button("BUY ₽%s" % _fmt_number(cfg["buy_cost_per_30"]), C_PANEL)
	buy_btn.custom_minimum_size = Vector2(90, 22)
	buy_btn.disabled = GameManager.game_state.rubles < cfg["buy_cost_per_30"]
	buy_btn.pressed.connect(func():
		AmmoSystem.buy_ammo(captured_ammo_type)
	)
	row.add_child(buy_btn)

	if count < min_raid:
		_ammo_vbox.add_child(_label("⚠ INSUFFICIENT AMMO — CANNOT DEPLOY", C_RED, 9))
	elif count < optimal:
		var penalty_pct := int(AmmoSystem.get_fail_penalty(weapon_id) * 100.0)
		_ammo_vbox.add_child(_label("▲ LOW AMMO  +%d%% FAIL RISK" % penalty_pct, C_ACCENT, 9))

	var is_deployed: bool = GameManager.game_state.operator.is_deployed
	_deploy_btn.disabled = is_deployed or not AmmoSystem.can_deploy(weapon_id) or _result_popup_visible

func _refresh_inventory() -> void:
	for child in _inventory_list.get_children():
		child.queue_free()

	var inventory: Array = GameManager.game_state.inventory
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

		var tier: int = item.get("tier", 0)
		if tier >= 1 and item.get("category", "") != "weapon":
			var tier_lbl = _label("T%d" % tier, _tier_color(tier), 9)
			tier_lbl.custom_minimum_size.x = 20
			row.add_child(tier_lbl)
			var ql := _quality_label(item.get("quality", "standard"))
			if not ql.is_empty():
				row.add_child(_label(ql, _quality_color(item.get("quality", "standard")), 9))
		else:
			var rarity_color := _rarity_color(item.get("rarity", "common"))
			row.add_child(_label(item.get("rarity", "").to_upper(), rarity_color, 9))

		var captured_item = item
		if item.get("category") == "weapon":
			var equip_btn = _button("EQUIP", C_GREEN)
			equip_btn.custom_minimum_size = Vector2(48, 20)
			equip_btn.pressed.connect(func():
				GameManager.equip_item(captured_item, "weapon")
				_refresh_equipment()
				_refresh_inventory()
				if _gun_mod_panel.visible:
					_refresh_gun_mod_panel()
			)
			row.add_child(equip_btn)
			var w_sell_btn = _button("SELL", C_PANEL)
			w_sell_btn.custom_minimum_size = Vector2(42, 20)
			w_sell_btn.pressed.connect(func(): GameManager.sell_item(captured_item))
			row.add_child(w_sell_btn)
		else:
			var sell_btn = _button("SELL", C_PANEL)
			sell_btn.custom_minimum_size = Vector2(42, 20)
			sell_btn.pressed.connect(func(): GameManager.sell_item(captured_item))
			row.add_child(sell_btn)

			var list_btn = _button("LIST", C_BORDER)
			list_btn.custom_minimum_size = Vector2(42, 20)
			list_btn.pressed.connect(func(): _open_list_dialog(captured_item))
			row.add_child(list_btn)

func _tier_color(tier: int) -> Color:
	var rarities := ["", "common", "uncommon", "rare", "epic"]
	return _rarity_color(rarities[tier] if tier >= 1 and tier <= 4 else "common")

func _quality_label(quality: String) -> String:
	match quality:
		"refined":    return "정제"
		"pristine":   return "순정"
		"masterwork": return "장인"
		_:            return ""

func _quality_color(quality: String) -> Color:
	match quality:
		"refined":    return Color(0.3, 0.7, 0.3)
		"pristine":   return Color(0.3, 0.5, 0.9)
		"masterwork": return Color(0.7, 0.3, 0.9)
		_:            return C_DIM

func _refresh_gun_mod_panel() -> void:
	for c in _gun_mod_slots_vbox.get_children(): c.queue_free()
	for c in _gun_mod_stats_vbox.get_children(): c.queue_free()

	var weapon = GameManager.game_state.equipment.get("weapon")
	if weapon == null:
		_gun_mod_slots_vbox.add_child(_label("No weapon equipped", C_DIM, 10))
		return

	_gun_mod_slots_vbox.add_child(_label(weapon.get("name", "?").to_upper(), C_ACCENT, 11))

	for slot in GunModSystem.get_available_slots(weapon):
		var captured_slot: String = slot
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_gun_mod_slots_vbox.add_child(row)

		var slot_lbl = _label(slot.to_upper().replace("_", " "), C_DIM, 9)
		slot_lbl.custom_minimum_size.x = 80
		row.add_child(slot_lbl)

		var mods: Dictionary = weapon.get("mods", {})
		if slot in mods:
			var equipped_mod: Dictionary = mods[slot]
			var mod_name = _label(equipped_mod.get("name", "?"), C_TEXT, 9)
			mod_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(mod_name)

			var tier: int = equipped_mod.get("tier", 0)
			var tier_lbl = _label("T%d" % tier, _tier_color(tier), 8)
			tier_lbl.custom_minimum_size.x = 18
			row.add_child(tier_lbl)

			var eq_ql := _quality_label(equipped_mod.get("quality", "standard"))
			if not eq_ql.is_empty():
				row.add_child(_label(eq_ql, _quality_color(equipped_mod.get("quality", "standard")), 8))

			var bonus_pct := int(equipped_mod.get("efficiency_bonus", 0.0) * 100.0)
			row.add_child(_label("+%d%%" % bonus_pct, C_GREEN, 8))

			var det_btn = _button("✕", C_RED)
			det_btn.custom_minimum_size = Vector2(22, 22)
			det_btn.pressed.connect(func():
				GunModSystem.detach_mod(weapon, captured_slot)
				_refresh_gun_mod_panel()
				_refresh_inventory()
				_refresh_equipment()
			)
			row.add_child(det_btn)
		else:
			var empty_lbl = _label("[ empty ]", C_DIM, 9)
			empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(empty_lbl)

	_gun_mod_slots_vbox.add_child(_label("AVAILABLE MODS", C_ACCENT, 10))
	var compatible := GunModSystem.get_compatible_mods(weapon, GameManager.game_state.inventory)
	if compatible.is_empty():
		_gun_mod_slots_vbox.add_child(_label("No compatible mods in inventory", C_DIM, 9))

	for mod in compatible:
		var captured_mod = mod
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_gun_mod_slots_vbox.add_child(row)

		var n = _label(mod.get("name", "?"), C_TEXT, 9)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)

		var tier: int = mod.get("tier", 0)
		var tier_lbl = _label("T%d" % tier, _tier_color(tier), 8)
		tier_lbl.custom_minimum_size.x = 18
		row.add_child(tier_lbl)

		var bonus_pct := int(mod.get("efficiency_bonus", 0.0) * 100.0)
		row.add_child(_label("+%d%%" % bonus_pct, C_GREEN, 8))

		var att_btn = _button("ATTACH", C_GREEN)
		att_btn.custom_minimum_size = Vector2(55, 22)
		att_btn.pressed.connect(func():
			GunModSystem.attach_mod(weapon, captured_mod)
			_refresh_gun_mod_panel()
			_refresh_inventory()
			_refresh_equipment()
		)
		row.add_child(att_btn)

	_gun_mod_stats_vbox.add_child(_label("EFFICIENCY", C_ACCENT, 11))
	var total_bonus := 0.0
	var total_loot := 0.0
	var total_fail_red := 0.0
	for slot in GunModSystem.get_available_slots(weapon):
		var mods: Dictionary = weapon.get("mods", {})
		if slot not in mods:
			continue
		var m: Dictionary = mods[slot]
		var bonus: float = m.get("efficiency_bonus", 0.0)
		total_bonus += bonus
		total_loot += m.get("loot_bonus", 0.0)
		total_fail_red += m.get("fail_reduction", 0.0)
		var row = HBoxContainer.new()
		_gun_mod_stats_vbox.add_child(row)
		var k = _label(slot.replace("_", " ").to_upper(), C_DIM, 9)
		k.custom_minimum_size.x = 90
		row.add_child(k)
		var tier: int = m.get("tier", 0)
		var quality: String = m.get("quality", "standard")
		var tier_str := "T%d" % tier
		if quality != "standard":
			tier_str += "·%s" % _quality_label(quality)
		row.add_child(_label("%s  +%d%%" % [tier_str, int(bonus * 100.0)], _tier_color(tier), 9))

	var eff_row = HBoxContainer.new()
	_gun_mod_stats_vbox.add_child(eff_row)
	var total_lbl = _label("TOTAL", C_ACCENT, 9)
	total_lbl.custom_minimum_size.x = 90
	eff_row.add_child(total_lbl)
	var eff_pct := clampf(1.0 + total_bonus, 1.0, 1.5) * 100.0
	eff_row.add_child(_label("%.0f%%" % eff_pct, C_ACCENT, 9))

	if total_loot > 0.0:
		var lr = HBoxContainer.new()
		_gun_mod_stats_vbox.add_child(lr)
		var ll = _label("LOOT BONUS", C_ACCENT, 9)
		ll.custom_minimum_size.x = 90
		lr.add_child(ll)
		lr.add_child(_label("+%.0f%%" % (total_loot * 100.0), C_GREEN, 9))

	if total_fail_red > 0.0:
		var fr = HBoxContainer.new()
		_gun_mod_stats_vbox.add_child(fr)
		var fl = _label("FAIL RISK", C_ACCENT, 9)
		fl.custom_minimum_size.x = 90
		fr.add_child(fl)
		fr.add_child(_label("-%.0f%%p" % (total_fail_red * 100.0), C_GREEN, 9))

# ── Black Market ─────────────────────────────────────────────────────────────

func _on_market_pressed() -> void:
	_market_tab = "browse"
	_refresh_market_panel()
	_market_panel.show()

func _select_market_tab(tab: String) -> void:
	_market_tab = tab
	_refresh_market_panel()

func _on_market_tick() -> void:
	# Per-second updates: only rewrite countdown text in place. Full row rebuilds
	# happen via market_refreshed / listings_changed signals, so we avoid freeing
	# buttons mid-click and resetting scroll every second.
	if not _market_panel.visible:
		return
	if _market_tab == "browse":
		var rs: int = MarketSystem.get_seconds_to_refresh()
		_market_refresh_label.text = "다음 갱신  %02d:%02d" % [floori(rs / 60.0), rs % 60]
	for d in _market_dyn:
		var lbl: Label = d["lbl"]
		if not is_instance_valid(lbl):
			continue
		lbl.text = _dyn_text(d["kind"], d["data"])

func _dyn_text(kind: String, data: Dictionary) -> String:
	if kind == "firesale":
		var left := int(float(data.get("expire", 0.0)) - float(data.get("age", 0.0)))
		return "급처 %ds" % max(0, left)
	# kind == "sale"
	var sell_at: float = float(data.get("sell_at", -1.0))
	var remain := int(max(0.0, sell_at - float(data.get("elapsed_online", 0.0))))
	var tag := "급매" if sell_at <= 30.0 else "판매중"
	return "%s %02d:%02d" % [tag, floori(remain / 60.0), remain % 60]

func _on_market_changed() -> void:
	if _market_panel.visible:
		_refresh_market_panel()

func _on_listing_sold(item: Dictionary, price: int) -> void:
	_notify("✔ %s 판매  ₽%s" % [item.get("name", "?"), _fmt_number(price)], C_GREEN)

func _build_market_panel() -> Control:
	var overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_market_panel.hide()
	)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 500)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_stylebox(C_PANEL, C_BORDER))
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hdr = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vbox.add_child(hdr)
	var title = _label("BLACK MARKET", C_ACCENT, 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	var close_btn = _button("✕", C_RED)
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(func(): _market_panel.hide())
	hdr.add_child(close_btn)

	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	vbox.add_child(tabs)
	_market_browse_btn = _button("BROWSE", C_PANEL)
	_market_browse_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_browse_btn.pressed.connect(_select_market_tab.bind("browse"))
	tabs.add_child(_market_browse_btn)
	_market_listings_btn = _button("MY LISTINGS", C_PANEL)
	_market_listings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_listings_btn.pressed.connect(_select_market_tab.bind("listings"))
	tabs.add_child(_market_listings_btn)

	_market_refresh_label = _label("", C_DIM, 9)
	vbox.add_child(_market_refresh_label)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_market_content_vbox = VBoxContainer.new()
	_market_content_vbox.add_theme_constant_override("separation", 4)
	_market_content_vbox.custom_minimum_size.x = 410
	scroll.add_child(_market_content_vbox)

	return overlay

func _refresh_market_panel() -> void:
	if _market_content_vbox == null:
		return
	# Highlight the active tab.
	_market_browse_btn.add_theme_stylebox_override("normal",
		_make_stylebox(C_BORDER if _market_tab == "browse" else C_PANEL, C_ACCENT if _market_tab == "browse" else C_BORDER))
	_market_listings_btn.add_theme_stylebox_override("normal",
		_make_stylebox(C_BORDER if _market_tab == "listings" else C_PANEL, C_ACCENT if _market_tab == "listings" else C_BORDER))

	for c in _market_content_vbox.get_children(): c.queue_free()
	_market_dyn.clear()

	if _market_tab == "browse":
		var rs: int = MarketSystem.get_seconds_to_refresh()
		_market_refresh_label.text = "다음 갱신  %02d:%02d" % [floori(rs / 60.0), rs % 60]
		_build_browse_rows()
	else:
		var my := MarketSystem.get_my_listings()
		_market_refresh_label.text = "내 매물  %d / %d" % [my.size(), MarketSystem.MAX_LISTINGS]
		_build_listing_rows(my)

func _build_browse_rows() -> void:
	var listings := MarketSystem.get_browse_listings()
	if listings.is_empty():
		_market_content_vbox.add_child(_label("매물 없음 — 잠시 후 갱신됩니다", C_DIM, 10))
		return
	for i in listings.size():
		var listing: Dictionary = listings[i]
		var item: Dictionary = listing.get("item", {})
		var idx := i
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_market_content_vbox.add_child(row)

		var name_lbl = _label(item.get("name", "?"), C_TEXT, 10)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var tier: int = item.get("tier", 0)
		if tier >= 1:
			row.add_child(_label("T%d" % tier, _tier_color(tier), 9))
			var ql := _quality_label(item.get("quality", "standard"))
			if not ql.is_empty():
				row.add_child(_label(ql, _quality_color(item.get("quality", "standard")), 9))

		if listing.get("firesale", false):
			var fs_lbl = _label(_dyn_text("firesale", listing), C_RED, 9)
			row.add_child(fs_lbl)
			_market_dyn.append({"lbl": fs_lbl, "data": listing, "kind": "firesale"})

		var price: int = listing.get("price", 0)
		var buy_btn = _button("₽%s" % _fmt_number(price), C_PANEL)
		buy_btn.custom_minimum_size = Vector2(72, 22)
		buy_btn.disabled = GameManager.game_state.rubles < price
		buy_btn.pressed.connect(func(): MarketSystem.buy_listing(idx))
		row.add_child(buy_btn)

func _build_listing_rows(my: Array) -> void:
	if my.is_empty():
		_market_content_vbox.add_child(_label("등록한 매물이 없습니다", C_DIM, 10))
		_market_content_vbox.add_child(_label("인벤토리에서 LIST 버튼으로 등록하세요", C_DIM, 9))
		return
	for i in my.size():
		var L: Dictionary = my[i]
		var item: Dictionary = L.get("item", {})
		var idx := i
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_market_content_vbox.add_child(row)

		var name_lbl = _label(item.get("name", "?"), C_TEXT, 10)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		row.add_child(_label("₽%s" % _fmt_number(L.get("asking_price", 0)), C_ACCENT, 9))

		var sell_at: float = float(L.get("sell_at", -1.0))
		if sell_at < 0.0:
			row.add_child(_label("미판매(고가)", C_RED, 9))
		else:
			var sale_lbl = _label(_dyn_text("sale", L), C_GREEN, 9)
			row.add_child(sale_lbl)
			_market_dyn.append({"lbl": sale_lbl, "data": L, "kind": "sale"})

		var cancel_btn = _button("취소", C_PANEL)
		cancel_btn.custom_minimum_size = Vector2(44, 22)
		cancel_btn.pressed.connect(func(): MarketSystem.cancel_listing(idx))
		row.add_child(cancel_btn)

# ── List (sell) dialog ───────────────────────────────────────────────────────

func _open_list_dialog(item: Dictionary) -> void:
	if MarketSystem.get_my_listings().size() >= MarketSystem.MAX_LISTINGS:
		_notify("매물 슬롯이 가득 찼습니다 (%d개)" % MarketSystem.MAX_LISTINGS, C_RED)
		return
	_list_dialog_item = item
	var market_price := MarketSystem.get_market_price(item)
	_list_dialog_name_lbl.text = item.get("name", "?")
	_list_dialog_mkt_lbl.text = "현재 시세  ₽%s" % _fmt_number(market_price)
	_list_dialog_spin.max_value = maxi(market_price * 5, 1000)
	_list_dialog_spin.value = market_price
	_update_list_fee()
	_list_dialog.show()

func _update_list_fee() -> void:
	var asking := int(_list_dialog_spin.value)
	var fee := MarketSystem.get_listing_fee(asking)
	_list_dialog_fee_lbl.text = "등록 수수료 ₽%s (선지불·환불 불가)" % _fmt_number(fee)

func _build_list_dialog() -> Control:
	var overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.9)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	overlay.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_stylebox(C_PANEL, C_BORDER))
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(_label("거래소 등록", C_ACCENT, 13))
	_list_dialog_name_lbl = _label("?", C_TEXT, 11)
	vbox.add_child(_list_dialog_name_lbl)
	_list_dialog_mkt_lbl = _label("현재 시세  ₽0", C_DIM, 9)
	vbox.add_child(_list_dialog_mkt_lbl)

	var price_row = HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 6)
	vbox.add_child(price_row)
	price_row.add_child(_label("희망가", C_DIM, 10))
	_list_dialog_spin = SpinBox.new()
	_list_dialog_spin.min_value = 1
	_list_dialog_spin.max_value = 1_000_000
	_list_dialog_spin.step = 50
	_list_dialog_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_dialog_spin.value_changed.connect(func(_v): _update_list_fee())
	price_row.add_child(_list_dialog_spin)

	_list_dialog_fee_lbl = _label("등록 수수료 ₽0", C_DIM, 9)
	vbox.add_child(_list_dialog_fee_lbl)
	vbox.add_child(_label("시세보다 싸게 올릴수록 빨리 팔립니다 (최대 5분 내).", C_DIM, 8))

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)
	var cancel_btn = _button("취소", C_PANEL)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func(): _list_dialog.hide())
	btn_row.add_child(cancel_btn)
	var confirm_btn = _button("등록", C_ACCENT)
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(_on_list_confirm)
	btn_row.add_child(confirm_btn)

	return overlay

func _on_list_confirm() -> void:
	var asking := int(_list_dialog_spin.value)
	if MarketSystem.list_item(_list_dialog_item, asking):
		_list_dialog.hide()
		_notify("거래소에 등록했습니다", C_GREEN)
	else:
		_notify("등록 실패 — 루블 부족 또는 슬롯 초과", C_RED)

func _notify(text: String, color: Color = C_GREEN) -> void:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _make_stylebox(C_PANEL, color))
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	p.offset_top = 36
	p.offset_left = 40
	p.offset_right = -40
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl = _label(text, color, 11)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(lbl)
	add_child(p)
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)

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
	b.add_theme_stylebox_override("normal",  _make_stylebox(bg, C_BORDER))
	b.add_theme_stylebox_override("hover",   _make_stylebox(bg.lightened(0.15), C_ACCENT))
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
	s.corner_radius_top_left    = 2
	s.corner_radius_top_right   = 2
	s.corner_radius_bottom_left  = 2
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
	if n >= 1_000_000: return "%.1fM" % (n / 1_000_000.0)
	if n >= 1_000:     return "%.1fk" % (n / 1_000.0)
	return str(n)
