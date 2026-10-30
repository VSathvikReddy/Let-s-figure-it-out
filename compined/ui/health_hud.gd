extends CanvasLayer
## The player's health bar (top left). Copied from the sinan HUD, health part
## only. The layout and colours live in health_hud.tscn; this script connects
## the bars to the player's health and adds a little juice:
##   - a light "damage" bar that catches up with the red bar after a hit
##   - the panel shakes when she is hit
##   - the bar pulses red like a heartbeat when her health is low
##
## Needed nodes (unique names): %HealthBar, %TrailBar, %Panel. Optional: %Value.

## Below this part of her max health the heartbeat pulse starts.
@export_range(0.0, 1.0) var low_health_ratio := 0.4
## Pause before the light "damage" bar catches up with the red bar.
@export var trail_delay := 0.35
@export var trail_duration := 0.45
@export var shake_strength := 6.0

@onready var health_bar: ProgressBar = %HealthBar
@onready var trail_bar: ProgressBar = %TrailBar
@onready var panel: Control = %Panel
@onready var value_label: Label = get_node_or_null("%Value")

var _player: Node
var _trail_tween: Tween
var _pulse_tween: Tween
var _low := false
var _panel_home_x := NAN


func _ready() -> void:
	_connect_player.call_deferred()   # the player may be ready after us


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not _player.has_signal("health_changed"):
		push_warning("Health HUD: no player with a health_changed signal found")
		return
	_player.health_changed.connect(_on_health_changed)
	_set_bars(_player.health, _player.max_health, false)


func _on_health_changed(current: float, maximum: float) -> void:
	_set_bars(current, maximum, true)


func _set_bars(current: float, maximum: float, animate: bool) -> void:
	var dropped := current < health_bar.value
	health_bar.max_value = maximum
	trail_bar.max_value = maximum
	health_bar.value = current
	if value_label:
		value_label.text = "%d / %d" % [ceili(current), roundi(maximum)]

	if _trail_tween:
		_trail_tween.kill()
	if animate and dropped:
		_trail_tween = create_tween()
		_trail_tween.tween_interval(trail_delay)
		_trail_tween.tween_property(trail_bar, "value", current, trail_duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_shake()
	else:
		trail_bar.value = current

	var low := maximum > 0.0 and current / maximum <= low_health_ratio
	if low != _low:
		_low = low
		_update_pulse()


func _shake() -> void:
	if is_nan(_panel_home_x):
		_panel_home_x = panel.position.x
	var shake := create_tween()
	for i in 4:
		shake.tween_property(panel, "position:x", _panel_home_x + randf_range(-shake_strength, shake_strength), 0.04)
	shake.tween_property(panel, "position:x", _panel_home_x, 0.05)


## Heartbeat at low health: the bar flashes red over and over.
func _update_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	health_bar.modulate = Color.WHITE
	if not _low:
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(health_bar, "modulate", Color(1.6, 0.7, 0.7), 0.12)
	_pulse_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.3)
	_pulse_tween.tween_interval(0.25)
