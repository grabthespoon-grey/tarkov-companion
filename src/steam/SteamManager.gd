extends Node

# GodotSteam integration layer.
# Install GodotSteam from https://godotsteam.com/ to enable live Steam features.
# _steam is fetched via Engine.get_singleton() so the parser never sees Steam.*
# directly — this lets the project run without GodotSteam installed.

signal inventory_refreshed(items: Array)

const APP_ID = 480  # Replace with your Steam App ID after Steamworks registration

var is_online: bool = false
var steam_id: int = 0
var steam_name: String = "Operator"

var _steam: Variant = null  # holds the Steam singleton when available

func _ready() -> void:
	_try_init()

func _try_init() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("SteamManager: GodotSteam not installed — running offline")
		return

	_steam = Engine.get_singleton("Steam")

	var result: Dictionary = _steam.steamInitEx(false)
	if result.get("status", -1) != 1:
		push_warning("SteamManager: Steam init failed — is Steam running?")
		_steam = null
		return

	is_online = true
	steam_id   = _steam.getSteamID()
	steam_name = _steam.getPersonaName()
	print("SteamManager: logged in as %s (%d)" % [steam_name, steam_id])

	_steam.inventory_result_ready.connect(_on_inventory_result)

func _process(_delta: float) -> void:
	if _steam != null:
		_steam.run_callbacks()

# ── Inventory ──────────────────────────────────────────────────────────────

func get_steam_inventory() -> void:
	if _steam == null:
		emit_signal("inventory_refreshed", [])
		return
	_steam.getAllItems()

func _on_inventory_result(result: int, handle: int) -> void:
	if result != 1:
		return
	var items: Array = _steam.getResultItems(handle)
	_steam.destroyResult(handle)
	emit_signal("inventory_refreshed", items)

func grant_promo_item(item_def_id: int) -> void:
	if _steam == null:
		return
	_steam.addPromoItem(item_def_id)

# ── Trading ────────────────────────────────────────────────────────────────

func open_trade_with(partner_steam_id: int) -> void:
	if _steam == null:
		return
	_steam.activateGameOverlayToUser("tradingcard", partner_steam_id)

func open_market_listing(item_def_id: int) -> void:
	OS.shell_open("https://steamcommunity.com/market/listings/%d/item_%d" % [APP_ID, item_def_id])

func open_steam_store() -> void:
	OS.shell_open("steam://store/%d" % APP_ID)

# ── Achievements ───────────────────────────────────────────────────────────

func unlock_achievement(api_name: String) -> void:
	if _steam == null:
		return
	_steam.setAchievement(api_name)
	_steam.storeStats()
