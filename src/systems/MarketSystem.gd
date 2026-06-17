extends Node
# Black Market — virtual marketplace simulation.
# Browse pool is transient (regenerated every REFRESH_INTERVAL). The player's
# own listings and the per-item price index live in game_state.market and are
# persisted. Sales only progress while online (driven by this node's own timer,
# independent of raids — same pattern as AmmoSystem).

signal market_refreshed()
signal listing_sold(item: Dictionary, price: int)
signal listings_changed()

const REFRESH_INTERVAL  := 300.0   # browse pool + index drift cadence (sec)
const FIRESALE_EXPIRE   := 30.0    # fire-sale listings vanish quickly (sec)
const MAX_LISTING_EXPIRE := 300.0  # unsold listing returns after this (online sec)
const MAX_LISTINGS      := 5
const FEE_RATE          := 0.05
const INDEX_MIN         := 0.6
const INDEX_MAX         := 1.6

var _browse: Array = []            # [{item, price, firesale, expire, age}]
var _tick_timer: Timer
var _refresh_accum: float = 0.0

func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)
	_tick_timer.start()
	# Deferred so GameManager has loaded the save before we read level/market.
	call_deferred("_refresh_browse")

# ── State access ────────────────────────────────────────────────────────────

func _market_state() -> Dictionary:
	var gs: Dictionary = GameManager.game_state
	if "market" not in gs or typeof(gs["market"]) != TYPE_DICTIONARY:
		gs["market"] = {"index": {}, "listings": []}
	return gs["market"]

func get_market_index(item_id: String) -> float:
	var idx: Dictionary = _market_state()["index"]
	if item_id not in idx:
		idx[item_id] = 1.0
	return float(idx[item_id])

func get_market_price(item: Dictionary) -> int:
	return int(round(float(item.get("base_value", 100)) * get_market_index(item.get("id", ""))))

func get_seconds_to_refresh() -> int:
	return int(max(0.0, REFRESH_INTERVAL - _refresh_accum))

func get_browse_listings() -> Array:
	return _browse

func get_my_listings() -> Array:
	return _market_state()["listings"]

# ── Tick loop ───────────────────────────────────────────────────────────────

func _on_tick() -> void:
	_advance_listings(1.0)
	_advance_browse(1.0)
	_refresh_accum += 1.0
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_drift_index()
		_refresh_browse()

func _advance_listings(delta: float) -> void:
	var listings: Array = _market_state()["listings"]
	var changed := false
	var i := 0
	while i < listings.size():
		var L: Dictionary = listings[i]
		L["elapsed_online"] = float(L.get("elapsed_online", 0.0)) + delta
		var sell_at: float = float(L.get("sell_at", -1.0))
		if sell_at >= 0.0 and L["elapsed_online"] >= sell_at:
			var price: int = int(L.get("asking_price", 0))
			GameManager.game_state.rubles += price
			GameManager.rubles_changed.emit(GameManager.game_state.rubles)
			emit_signal("listing_sold", L.get("item", {}), price)
			listings.remove_at(i)
			changed = true
			continue
		if L["elapsed_online"] >= float(L.get("expire_at", MAX_LISTING_EXPIRE)):
			GameManager.game_state.inventory.append(L.get("item", {}))
			GameManager.inventory_changed.emit()
			listings.remove_at(i)
			changed = true
			continue
		i += 1
	if changed:
		emit_signal("listings_changed")
		SaveManager.save_game()

func _advance_browse(delta: float) -> void:
	var changed := false
	var i := 0
	while i < _browse.size():
		var b: Dictionary = _browse[i]
		if float(b.get("expire", -1.0)) >= 0.0:
			b["age"] = float(b.get("age", 0.0)) + delta
			if b["age"] >= float(b["expire"]):
				_browse.remove_at(i)
				changed = true
				continue
		i += 1
	if changed:
		emit_signal("market_refreshed")

# ── Index drift (random walk + mean reversion) ──────────────────────────────

func _drift_index() -> void:
	var idx: Dictionary = _market_state()["index"]
	for item_id in idx.keys():
		var v: float = float(idx[item_id])
		var drift := randf_range(-0.08, 0.08)
		var revert := (1.0 - v) * 0.10
		idx[item_id] = clampf(v + drift + revert, INDEX_MIN, INDEX_MAX)

# ── Browse generation ───────────────────────────────────────────────────────

func _refresh_browse() -> void:
	_browse.clear()
	var level: int = int(GameManager.game_state.operator.get("level", 1))
	var n := randi_range(6, 8)
	for _i in range(n):
		var tier := _roll_tier(level)
		var inst := LootSystem.make_market_instance(tier)
		if inst.is_empty():
			continue
		var priced := _roll_price(inst)
		_browse.append({
			"item": inst,
			"price": priced["price"],
			"firesale": priced["firesale"],
			"expire": FIRESALE_EXPIRE if priced["firesale"] else -1.0,
			"age": 0.0,
		})
	emit_signal("market_refreshed")

func _roll_tier(level: int) -> int:
	var r := randf()
	if level <= 2:
		return 1 if r < 0.70 else 2
	elif level <= 5:
		if r < 0.20: return 1
		elif r < 0.80: return 2
		else: return 3
	elif level <= 9:
		if r < 0.25: return 2
		elif r < 0.90: return 3
		else: return 4
	else:
		return 3 if r < 0.50 else 4

func _roll_price(item: Dictionary) -> Dictionary:
	var market := float(get_market_price(item))
	var r := randf()
	var variance: float
	var firesale := false
	if r < 0.02:
		variance = randf_range(0.50, 0.75)
		firesale = true
	elif r < 0.10:
		variance = randf_range(1.30, 2.00)
	else:
		variance = randf_range(0.85, 1.20)
	return {"price": int(round(market * variance)), "firesale": firesale}

# ── Buying ──────────────────────────────────────────────────────────────────

func buy_listing(index: int) -> bool:
	if index < 0 or index >= _browse.size():
		return false
	var listing: Dictionary = _browse[index]
	var price: int = int(listing.get("price", 0))
	if GameManager.game_state.rubles < price:
		return false
	GameManager.game_state.rubles -= price
	GameManager.game_state.inventory.append(listing["item"].duplicate(true))
	_browse.remove_at(index)
	GameManager.rubles_changed.emit(GameManager.game_state.rubles)
	GameManager.inventory_changed.emit()
	SaveManager.save_game()
	emit_signal("market_refreshed")
	return true

# ── Selling (player listings) ───────────────────────────────────────────────

func get_listing_fee(asking_price: int) -> int:
	return int(round(asking_price * FEE_RATE))

func list_item(item: Dictionary, asking_price: int) -> bool:
	var listings: Array = _market_state()["listings"]
	if listings.size() >= MAX_LISTINGS:
		return false
	if asking_price <= 0:
		return false
	var fee := get_listing_fee(asking_price)
	if GameManager.game_state.rubles < fee:
		return false
	if not GameManager.game_state.inventory.has(item):
		return false
	GameManager.game_state.rubles -= fee
	GameManager.game_state.inventory.erase(item)
	var market := float(get_market_price(item))
	var ratio := asking_price / market if market > 0.0 else 99.0
	listings.append({
		"item": item,
		"asking_price": asking_price,
		"elapsed_online": 0.0,
		"sell_at": _roll_sell_time(ratio),
		"expire_at": MAX_LISTING_EXPIRE,
	})
	GameManager.rubles_changed.emit(GameManager.game_state.rubles)
	GameManager.inventory_changed.emit()
	emit_signal("listings_changed")
	SaveManager.save_game()
	return true

# Sale time in online seconds, compressed so all bands resolve within 5 min.
func _roll_sell_time(ratio: float) -> float:
	if ratio <= 0.75:    return randf_range(0.0, 30.0)
	elif ratio <= 0.95:  return randf_range(30.0, 90.0)
	elif ratio <= 1.10:  return randf_range(90.0, 180.0)
	elif ratio <= 1.30:  return randf_range(180.0, 300.0)
	else:                return -1.0   # too expensive — never sells, expires

func cancel_listing(index: int) -> bool:
	var listings: Array = _market_state()["listings"]
	if index < 0 or index >= listings.size():
		return false
	var L: Dictionary = listings[index]
	GameManager.game_state.inventory.append(L.get("item", {}))
	listings.remove_at(index)
	GameManager.inventory_changed.emit()
	emit_signal("listings_changed")
	SaveManager.save_game()
	return true
