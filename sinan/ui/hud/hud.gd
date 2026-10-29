extends CanvasLayer
## Player HUD. The layout and styling live in hud.tscn (Control nodes, edit them
## in the editor). This script only connects the bars to the player's health and
## adds a little juice with Tweens: a trailing "damage" bar, a panel shake and a
## heartbeat pulse at low health.
##
## Required nodes (unique names): %HealthBar, %TrailBar, %Panel.
## Optional: %Value (Label, "3 / 5") and %Heart (any Control that pulses). If
## there is no %Heart, the health bar itself pulses at low health.
## Coins: %Coins (Label) and %CoinPanel (bumps when coins come in).
## Entropy: %Entropy (Label, optional).

## Below this fraction of max health the heartbeat pulse starts.
@export_range(0.0, 1.0) var low_health_ratio := 0.4
## Pause before the light "damage" bar catches up with the red bar.
@export var trail_delay := 0.35
@export var trail_duration := 0.45
@export var shake_strength := 6.0

@export_group("Coins")
## Size of the coin counter bump when coins come in.
@export var coin_bump := 1.15
## Seconds between saving collected coins to disk.
@export var save_interval := 3.0
@export_group("")

const ClarityBar := preload("res://sinan/ui/hud/clarity_bar.gd")
const DebugOverlay := preload("res://sinan/ui/debug/debug_overlay.gd")

@onready var health_bar: ProgressBar = %HealthBar
@onready var trail_bar: ProgressBar = %TrailBar
@onready var panel: Control = %Panel
@onready var value_label: Label = get_node_or_null("%Value")
@onready var heart: Control = get_node_or_null("%Heart")
@onready var coins_label: Label = get_node_or_null("%Coins")
@onready var coin_panel: Control = get_node_or_null("%CoinPanel")
@onready var entropy_label: Label = get_node_or_null("%Entropy")

var _player: Node
var _trail_tween: Tween
var _pulse_tween: Tween
var _low := false
var _panel_home_x := NAN
var _shown_coins := -1
var _save_t := 3.0


func _ready() -> void:
	add_to_group("progress_listeners")
	_update_coins(false)
	_connect_player.call_deferred()
	add_child(ClarityBar.new())
	# FPS meter on its own top layer, so it shows over the skill tree and menus
	var top := CanvasLayer.new()
	top.layer = 100
	top.add_child(preload("res://sinan/ui/hud/fps_meter.gd").new())
	add_child(top)
	_add_debug_overlay.call_deferred()


## F3 overlay lives in the world (it draws nav links and enemy states there).
func _add_debug_overlay() -> void:
	var world := get_parent()
	if world:
		world.add_child(DebugOverlay.new())


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not _player.has_signal("health_changed"):
		push_warning("HUD: no player with a health_changed signal found")
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
		_trail_tween.tween_property(trail_bar, "value", current, trail_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_shake()
		_bump(1.45)
	else:
		trail_bar.value = current
		if animate:
			_bump(1.25)  # healed

	var low := maximum > 0.0 and current / maximum <= low_health_ratio
	if low != _low:
		_low = low
		_update_pulse()


## The node that pulses: the heart if there is one, otherwise the health bar.
func _pulse_target() -> Control:
	return heart if heart else health_bar


func _shake() -> void:
	if is_nan(_panel_home_x):
		_panel_home_x = panel.position.x
	var tw := create_tween()
	for i in 4:
		tw.tween_property(panel, "position:x", _panel_home_x + randf_range(-shake_strength, shake_strength), 0.04)
	tw.tween_property(panel, "position:x", _panel_home_x, 0.05)


func _bump(amount: float) -> void:
	if heart == null:
		return  # scaling a bar inside a container looks wrong; the shake is enough
	heart.pivot_offset = heart.size * 0.5
	var tw := create_tween()
	tw.tween_property(heart, "scale", Vector2.ONE * amount, 0.08)
	tw.tween_property(heart, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _update_pulse() -> void:
	var target := _pulse_target()
	if _pulse_tween:
		_pulse_tween.kill()
	target.modulate = Color.WHITE
	if heart:
		heart.scale = Vector2.ONE
	if not _low:
		return
	# heartbeat: a quick red flash (plus a scale bump on the heart, if present)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(target, "modulate", Color(1.6, 0.7, 0.7), 0.12)
	if heart:
		heart.pivot_offset = heart.size * 0.5
		_pulse_tween.parallel().tween_property(heart, "scale", Vector2.ONE * 1.2, 0.12)
	_pulse_tween.tween_property(target, "modulate", Color.WHITE, 0.3)
	if heart:
		_pulse_tween.parallel().tween_property(heart, "scale", Vector2.ONE, 0.3)
	_pulse_tween.tween_interval(0.25)


# ---------------------------------------------------------------- coins

func _process(delta: float) -> void:
	# coins are saved in batches (not on every pickup)
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = save_interval
		Progress.save_if_dirty()


func _exit_tree() -> void:
	Progress.save_if_dirty()


## Called through the "progress_listeners" group.
func on_progress_changed() -> void:
	_update_coins(true)


func _update_coins(animate: bool) -> void:
	if coins_label == null:
		return
	if entropy_label:
		entropy_label.text = str(Progress.entropy())
	var c := Progress.coins()
	var gained := c > _shown_coins
	_shown_coins = c
	coins_label.text = str(c)
	if animate and gained and coin_panel:
		coin_panel.pivot_offset = coin_panel.size * 0.5
		var tw := create_tween()
		tw.tween_property(coin_panel, "scale", Vector2.ONE * coin_bump, 0.05)
		tw.tween_property(coin_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
