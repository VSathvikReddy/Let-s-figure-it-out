extends Node2D
## The priest's fire breath: a particle flame jet pouring out of the hood in a
## cone - a white-hot core at the mouth, billowing flame that slows, swells and
## rises as it cools, and dark soot rolling off the end.
## While it burns it hurts the player inside the cone (on a tick), ignites any
## smoke it touches, and scorches the painting at the end of the flame.
## Rotate the node to aim (0 = +x). Call start() / stop().
## The flame and soot are engine particle emitters (simulated in C++), so a
## crowd of priests breathing at once stays cheap.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const SmokeManager := preload("res://sinan/actors/enemies/priest/smoke_manager.gd")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")

@export var length := 300.0
@export var half_angle := deg_to_rad(18.0)
@export var damage := 0.5
@export var tick := 0.3
@export var paint_radius := 24.0
@export var paint_strength := 0.15
## Flame particles per second while breathing.
@export var flame_rate := 110.0
## Size of the flame particles as they leave the mouth / at their biggest.
@export var flame_size := Vector2(16, 46)

var active := false
var _tick := 0.0
var _fire: CPUParticles2D
var _soot: CPUParticles2D
var _light: PointLight2D


func _ready() -> void:
	z_index = 5
	var speed := length * 3.0  # with the damping below the jet reaches about `length`
	# flame: white-hot at the mouth, billows (swells), slows and rises as it cools
	_fire = FxLib.emitter({
		"one_shot": false, "amount": maxi(int(flame_rate * 0.55), 8), "life": 0.5, "life_rand": 0.2,
		"direction": Vector2.RIGHT, "spread": rad_to_deg(half_angle) * 0.75,
		"v_min": speed * 0.8, "v_max": speed * 1.05, "damp_min": speed * 1.25, "damp_max": speed * 1.25,
		"gravity": Vector2(0, -180), "texture": FxLib.glow(), "additive": true,
		"s_min": flame_size.x / 128.0 * 1.3, "s_max": flame_size.y / 128.0 * 1.1, "curve": _billow(),
		"spin_min": 0.0, "spin_max": 0.0,
		"ramp": FxLib.gradient([
			[0.0, Color(1.0, 0.85, 0.55, 0.65)], [0.2, Color(1.0, 0.5, 0.12, 0.75)],
			[0.5, Color(0.85, 0.22, 0.05, 0.6)], [0.8, Color(0.45, 0.07, 0.03, 0.3)],
			[1.0, Color(0.15, 0.03, 0.02, 0.0)]]),
	})
	_fire.emitting = false
	# soot rolling off the end of the flame
	_soot = FxLib.emitter({
		"one_shot": false, "amount": maxi(int(flame_rate * 0.15), 4), "life": 1.1, "life_rand": 0.3,
		"direction": Vector2(1.0, -0.6), "spread": 25.0, "v_min": 40.0, "v_max": 80.0,
		"gravity": Vector2(0, -120), "damp_min": 20.0, "damp_max": 40.0, "texture": FxLib.glow(),
		"s_min": flame_size.y / 128.0 * 0.9, "s_max": flame_size.y / 128.0 * 1.4, "curve": FxLib.grow(),
		"ramp": FxLib.gradient([
			[0.0, Color(0.15, 0.1, 0.1, 0.0)], [0.2, Color(0.14, 0.11, 0.12, 0.45)],
			[1.0, Color(0.2, 0.18, 0.2, 0.0)]]),
	})
	_soot.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_soot.emission_rect_extents = Vector2(length * 0.2, 6.0)
	_soot.position = Vector2(length * 0.7, 0)
	_soot.emitting = false
	add_child(_soot)
	add_child(_fire)
	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = Color(1.0, 0.45, 0.15)
	_light.energy = 0.0
	_light.texture_scale = length / 60.0
	_light.position = Vector2(length * 0.45, 0)
	add_child(_light)


## Swell fast, then shrink away as it cools.
static func _billow() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1.0, 0.5))
	return c


func start() -> void:
	active = true
	_tick = 0.0
	_fire.emitting = true
	_soot.emitting = true


func stop() -> void:
	active = false
	if _fire:
		_fire.emitting = false
		_soot.emitting = false


func _process(delta: float) -> void:
	_light.energy = move_toward(_light.energy, 1.8 if active else 0.0, delta * 8.0)


func _physics_process(delta: float) -> void:
	if not active:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = tick
	var origin := global_position
	var dir := Vector2.from_angle(global_rotation)
	SmokeManager.get_for(self).ignite_cone(origin, dir, half_angle, length)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("take_damage"):
		var to: Vector2 = p.global_position + Vector2(0, -10) - origin
		if to.length() <= length and absf(dir.angle_to(to)) <= half_angle + 0.12:
			p.take_damage(damage, origin, 260.0, false, get_parent() as Node2D)  # the priest breathing it
	# scorch the painting where the flame ends
	var tip := origin + dir * length * randf_range(0.7, 1.0)
	var pick := PaintPicker.pick(get_tree().current_scene, tip)
	if not pick.is_empty():
		Paint.hit(self, pick["layer"], pick["local"], paint_radius, paint_strength, Paint.Kind.BURN, &"fire")
