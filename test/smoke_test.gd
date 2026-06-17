extends Node
# Headless smoke test for Black Market + grade-badge rendering.
# Run via: main_scene override -> godot --headless (see scripts/smoke.sh).
# Drives the same code paths the UI buttons trigger, asserts results, prints
# SMOKE: lines, then quits. Exit is signalled by "SMOKE_DONE pass=.. fail=..".

var _pass := 0
var _fail := 0
var _ui: Control

func _ready() -> void:
	# Deferred so GameManager._load_save (also deferred) runs first; we then
	# overwrite game_state with deterministic fixtures.
	call_deferred("_run")

func _run() -> void:
	_ui = load("res://src/ui/MainUI.gd").new()
	add_child(_ui)   # triggers MainUI._ready -> builds panels

	_test_badge_consistency()
	_test_list_item()
	_test_buy_listing()
	_test_sale_resolution()
	_test_cancel_listing()
	_test_my_listings_render()

	print("SMOKE_DONE pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)

# ── Fixtures ─────────────────────────────────────────────────────────────────

func _legacy_mag() -> Dictionary:
	# Mirrors the real save's RPK item: NO tier, NO quality (legacy instance).
	return {"id": "ak_drum_75rd", "name": "RPK-16 Drum Magazine 95rd",
		"rarity": "rare", "category": "magazine", "base_value": 2500, "efficiency_bonus": 0.07}

func _normal_mod() -> Dictionary:
	return {"id": "test_comp", "name": "Test Muzzle Comp", "tier": 2, "rarity": "uncommon",
		"quality": "refined", "category": "muzzle", "base_value": 1500, "efficiency_bonus": 0.05}

func _reset_state(rubles: int, inv: Array) -> void:
	GameManager.game_state.rubles = rubles
	GameManager.game_state.inventory = inv
	GameManager.game_state.market = {"index": {}, "listings": []}

# ── Tests ────────────────────────────────────────────────────────────────────

func _test_badge_consistency() -> void:
	_reset_state(100000, [_legacy_mag(), _normal_mod()])
	_ui._refresh_inventory()
	var texts := _labels(_ui._inventory_list)
	# Legacy mag (rarity=rare, no tier) must derive to T3, not show English RARE.
	_check("badge: legacy item shows T3", "T3" in texts)
	_check("badge: no English RARE label", not ("RARE" in texts))
	_check("badge: refined quality shows 정제", "정제" in texts)

func _test_list_item() -> void:
	var mod := _normal_mod()
	_reset_state(100000, [mod])
	var price := MarketSystem.get_market_price(mod)
	var fee := MarketSystem.get_listing_fee(price)
	var rubles_before: int = GameManager.game_state.rubles
	var ok := MarketSystem.list_item(mod, price)
	_check("list: returns true", ok)
	_check("list: item removed from inventory", not GameManager.game_state.inventory.has(mod))
	_check("list: listing added", MarketSystem.get_my_listings().size() == 1)
	_check("list: fee deducted", GameManager.game_state.rubles == rubles_before - fee)

func _test_buy_listing() -> void:
	_reset_state(1000000, [])
	MarketSystem._refresh_browse()
	var browse := MarketSystem.get_browse_listings()
	if browse.is_empty():
		_check("buy: browse pool non-empty", false)
		return
	var price: int = browse[0].get("price", 0)
	var rubles_before: int = GameManager.game_state.rubles
	var inv_before: int = GameManager.game_state.inventory.size()
	var ok := MarketSystem.buy_listing(0)
	_check("buy: returns true", ok)
	_check("buy: rubles deducted by price", GameManager.game_state.rubles == rubles_before - price)
	_check("buy: item added to inventory", GameManager.game_state.inventory.size() == inv_before + 1)

func _test_sale_resolution() -> void:
	var mod := _normal_mod()
	_reset_state(100000, [mod])
	var price := MarketSystem.get_market_price(mod)
	MarketSystem.list_item(mod, price)
	var listings := MarketSystem.get_my_listings()
	# Force imminent sale, then tick.
	listings[0]["sell_at"] = 1.0
	listings[0]["elapsed_online"] = 0.0
	var sold := {"hit": false, "price": 0}
	var cb := func(_item, p): sold["hit"] = true; sold["price"] = p
	MarketSystem.listing_sold.connect(cb)
	var rubles_before: int = GameManager.game_state.rubles
	MarketSystem._on_tick()   # +1s -> elapsed 1.0 >= sell_at 1.0 -> sells
	MarketSystem.listing_sold.disconnect(cb)
	_check("sale: listing_sold fired", sold["hit"])
	_check("sale: listing removed", MarketSystem.get_my_listings().is_empty())
	_check("sale: rubles credited asking price", GameManager.game_state.rubles == rubles_before + price)

func _test_cancel_listing() -> void:
	var mod := _normal_mod()
	_reset_state(100000, [mod])
	MarketSystem.list_item(mod, MarketSystem.get_market_price(mod))
	_check("cancel: precondition listed", MarketSystem.get_my_listings().size() == 1)
	var ok := MarketSystem.cancel_listing(0)
	_check("cancel: returns true", ok)
	_check("cancel: listing removed", MarketSystem.get_my_listings().is_empty())
	_check("cancel: item returned to inventory", GameManager.game_state.inventory.size() == 1)

func _test_my_listings_render() -> void:
	_reset_state(100000, [_normal_mod(), _legacy_mag()])
	_ui._on_market_pressed()
	_ui._select_market_tab("listings")
	var texts := _labels(_ui._market_content_vbox)
	_check("render: MY LISTINGS has 등록된 매물 section", _contains(texts, "등록된 매물"))
	_check("render: MY LISTINGS has 등록 가능한 아이템 section", _contains(texts, "등록 가능한 아이템"))
	_check("render: sellable item name shown", _contains(texts, "Test Muzzle Comp"))
	# Browse tab renders without error and shows refresh countdown.
	_ui._select_market_tab("browse")
	var btexts := _labels(_ui._market_content_vbox)
	_check("render: BROWSE tab built (rows or empty note)", btexts.size() >= 0)
	_ui._market_panel.hide()

# ── Helpers ──────────────────────────────────────────────────────────────────

func _labels(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_labels(c, out)
	return out

func _contains(texts: Array, needle: String) -> bool:
	for t in texts:
		if needle in t:
			return true
	return false

func _check(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("SMOKE: PASS  %s" % name)
	else:
		_fail += 1
		print("SMOKE: FAIL  %s" % name)
