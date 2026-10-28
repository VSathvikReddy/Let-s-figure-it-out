extends Node2D
## Player machete (melee). Everything visual lives in machete.tscn:
##   Pivot/Blade (Sprite2D)   - swap the texture for your own art
##   Pivot/Hitbox (Area2D)    - resize the shape to fit the blade
##   Slash (Sprite2D)         - the swing arc
##   AnimationPlayer "swing"  - rotates the Pivot, flashes the arc and turns the
##                              hitbox on only during the cutting part of the swing
## This script just aims the swing, damages each enemy the hitbox touches once
## per swing, and adds hit feedback.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

@export var damage := 3.0
## Seconds between swings.
@export var cooldown := 0.4
## Small forward push given to the player on each swing.
@export var lunge_speed := 160.0
## Freeze frame on hit (seconds of real time, 0 = off).
@export var hit_stop := 0.05
@export var hit_shake := 0.15
@export var spark_color := Color(1.0, 0.95, 0.8)
## Hide the machete when it is not swinging.
@export var hide_when_idle := true
@export var swing_animation := &"swing"

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var hitbox: Area2D = $Pivot/Hitbox

var _cooldown_left := 0.0
var _already_hit: Array[Node] = []


func _ready() -> void:
	visible = not hide_when_idle
	anim.animation_finished.connect(_on_animation_finished)


func is_ready() -> bool:
	return _cooldown_left <= 0.0


## Start a swing toward `aim`. Returns false while on cooldown.
func swing(aim: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = cooldown
	_already_hit.clear()
	rotation = aim.angle()
	scale.y = -1.0 if aim.x < 0.0 else 1.0
	visible = true
	anim.stop()
	anim.play(swing_animation)
	return true


func _physics_process(delta: float) -> void:
	_cooldown_left -= delta
	if not anim.is_playing():
		return
	for body in hitbox.get_overlapping_bodies():
		if body in _already_hit or not body.has_method("take_hit"):
			continue
		_already_hit.append(body)
		body.take_hit(damage, global_position, HitInfo.make(HitInfo.SINGLE, &"machete", body.global_position))
		_hit_feedback(body)


func _hit_feedback(body: Node2D) -> void:
	var world := get_parent().get_parent()  # machete -> player -> level
	var at := body.global_position
	FxLib.burst(world, {
		"amount": 14, "life": 0.3, "v_min": 150.0, "v_max": 420.0,
		"direction": Vector2.RIGHT, "spread": 50.0, "texture": FxLib.streak(), "align": true,
		"angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"s_min": 0.25, "s_max": 0.5, "damp_min": 300.0, "damp_max": 600.0,
		"ramp": FxLib.fade_ramp(spark_color), "additive": true,
	}, at, (at - global_position).angle())
	FxLib.flash_light(world, at, spark_color, 1.6, 1.2, 0.12)
	get_tree().call_group("player", "add_trauma", hit_shake, global_position)
	if hit_stop > 0.0:
		FxLib.hit_stop(get_tree(), hit_stop)


func _on_animation_finished(_name: StringName) -> void:
	if hide_when_idle:
		visible = false
