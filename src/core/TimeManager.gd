extends Node

signal farm_completed(location_id: String, efficiency: float)
signal farm_progress_updated(progress: float, time_remaining: int)

var _farm_timer: Timer
var _current_location_id: String = ""
var _current_efficiency: float = 1.0
var _farm_duration: float = 0.0
var _farm_elapsed: float = 0.0
var _is_running: bool = false

func _ready() -> void:
	_farm_timer = Timer.new()
	_farm_timer.wait_time = 1.0
	_farm_timer.timeout.connect(_on_tick)
	add_child(_farm_timer)

func start_farm_timer(location_id: String, efficiency: float) -> void:
	var location_data = LootSystem.get_location(location_id)
	if location_data.is_empty():
		push_error("TimeManager: unknown location " + location_id)
		return

	_current_location_id = location_id
	_current_efficiency = efficiency
	_farm_duration = randf_range(
		location_data.get("min_time_minutes", 10),
		location_data.get("max_time_minutes", 20)
	) * 60.0
	_farm_elapsed = 0.0
	_is_running = true
	_farm_timer.start()

func stop_farm_timer() -> void:
	_is_running = false
	_farm_timer.stop()

func get_progress() -> float:
	if _farm_duration <= 0.0:
		return 0.0
	return clamp(_farm_elapsed / _farm_duration, 0.0, 1.0)

func get_time_remaining() -> int:
	return max(0, int(_farm_duration - _farm_elapsed))

func _on_tick() -> void:
	# Ammo regen is handled by AmmoSystem's own timer (runs always, not just
	# during raids), so it's intentionally not ticked here.
	if not _is_running:
		return
	_farm_elapsed += 1.0
	emit_signal("farm_progress_updated", get_progress(), get_time_remaining())
	if _farm_elapsed >= _farm_duration:
		_is_running = false
		_farm_timer.stop()
		emit_signal("farm_completed", _current_location_id, _current_efficiency)

func resume_from_save(elapsed_seconds: float, location_id: String, efficiency: float, duration: float) -> void:
	_current_location_id = location_id
	_current_efficiency = efficiency
	_farm_duration = duration
	_farm_elapsed = min(elapsed_seconds, duration)
	if _farm_elapsed >= duration:
		emit_signal("farm_completed", location_id, efficiency)
	else:
		_is_running = true
		_farm_timer.start()

func calculate_offline_raids(last_save_time: float, avg_duration_minutes: float = 15.0) -> int:
	var offline_seconds = Time.get_unix_time_from_system() - last_save_time
	offline_seconds = min(offline_seconds, 8.0 * 3600.0)
	return int(offline_seconds / (avg_duration_minutes * 60.0))
