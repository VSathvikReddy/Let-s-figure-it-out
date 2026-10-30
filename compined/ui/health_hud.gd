extends CanvasLayer
## The player's health (top left): a row of pixel hearts (heart_icon.gd).
## Each heart is worth `health_per_heart` points (1: one heart per health
## point). A heart that loses all of its points cracks and shatters and leaves
## a shadow; with more than 1 point per heart, losing part of it cracks it.
## The row shakes when she is hit, and the last heart beats when health is low.
## Inside the veil a countdown ring (veil_heal_timer.gd) shows when the next
## heart comes back.

## Health points in one heart (5 health / 1 = 5 hearts).
@export var health_per_heart := 1
## Size of each heart on screen, in px.
@export var heart_size := 40.0
## Below this part of her max health the last heart starts beating.
@export_range(0.0, 1.0) var low_health_ratio := 0.4
@export var shake_strength := 6.0

const HeartIcon := preload("res://compined/ui/heart_icon.gd")

@onready var row: HBoxContainer = %Hearts
@onready var heal_timer: Control = %VeilHealTimer

var _player: Node
var _hearts: Array = []
var _beat_timer := 0.0
var _low := false
var _home_x := NAN
var _shown_health := 0


func _ready() -> void:
	_connect_player.call_deferred()   # the player may be ready after us


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null or not _player.has_signal("health_changed"):
		push_warning("Health HUD: no player with a health_changed signal found")
		return
	_player.health_changed.connect(_on_health_changed)
	_make_hearts(_player.max_health)
	_shown_health = _player.health
	_show(_player.health, _player.max_health, false)


func _make_hearts(max_health: int) -> void:
	for heart in _hearts:
		heart.queue_free()
	_hearts.clear()
	for i in ceili(float(max_health) / health_per_heart):
		var heart := HeartIcon.new()
		heart.custom_minimum_size = Vector2(heart_size, heart_size)
		row.add_child(heart)
		_hearts.append(heart)


func _on_health_changed(current: float, maximum: float) -> void:
	if ceili(maximum / health_per_heart) != _hearts.size():
		_make_hearts(int(maximum))
	var hurt := current < _shown_health
	_shown_health = int(current)
	_show(int(current), int(maximum), true)
	if hurt:
		_shake()


## Heart number i holds health from i * health_per_heart up to the next one.
func _show(current: int, maximum: int, animate: bool) -> void:
	for i in _hearts.size():
		var left := clampi(current - i * health_per_heart, 0, health_per_heart)
		_hearts[i].show_health(left, health_per_heart, animate)
	_low = maximum > 0 and float(current) / maximum <= low_health_ratio and current > 0


func _process(delta: float) -> void:
	_update_heal_timer()
	if not _low:
		return
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		_beat_timer = 0.7
		var last := _last_living_heart()
		if last:
			last.beat()


## The veil countdown: shown only while she is healing in the veil.
func _update_heal_timer() -> void:
	var healing: bool = _player != null and _player.is_healing_in_veil()
	heal_timer.visible = healing
	if healing:
		heal_timer.progress = _player.veil_heal_time / _player.veil_heal_interval
		heal_timer.seconds_left = _player.veil_heal_interval - _player.veil_heal_time


func _last_living_heart() -> Control:
	for i in range(_hearts.size() - 1, -1, -1):
		if _hearts[i].state != HeartIcon.State.BROKEN:
			return _hearts[i]
	return null


func _shake() -> void:
	if is_nan(_home_x):
		_home_x = row.position.x
	var shake := create_tween()
	for i in 4:
		shake.tween_property(row, "position:x", _home_x + randf_range(-shake_strength, shake_strength), 0.04)
	shake.tween_property(row, "position:x", _home_x, 0.05)
