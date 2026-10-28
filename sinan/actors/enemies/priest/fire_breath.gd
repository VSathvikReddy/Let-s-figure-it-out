extends Node2D
## The priest's fire breath: a particle flame jet pouring out of the hood in a
## cone - a white-hot core at the mouth, billowing flame that slows, swells and
## rises as it cools, and dark soot rolling off the end.
## While it burns it hurts the player inside the cone (on a tick), ignites any
## smoke it touches, and scorches the painting at the end of the flame.
## Rotate the node to aim (0 = +x). Call start() / stop().

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const FireParticles := preload("res://sinan/fx/core/fire_particles.gd")
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
var _spawn := 0.0
var _fire: Node2D
var _soot: Node2D
var _light: PointLight2D


func _ready() -> void:
	z_index = 5
	_soot = FireParticles.new()
	_soot.additive = false
	_soot.buoyancy = 120.0
	_soot.drag = 1.5
	add_child(_soot)
	_fire = FireParticles.new()
	_fire.ramp = FxLib.gradient([
		[0.0, Color(1.0, 0.75, 0.35, 0.6)], [0.2, Color(1.0, 0.5, 0.12, 0.75)],
		[0.5, Color(0.85, 0.22, 0.05, 0.6)], [0.8, Color(0.45, 0.07, 0.03, 0.3)],
		[1.0, Color(0.15, 0.03, 0.02, 0.0)]])
	_fire.buoyancy = 180.0
	_fire.drag = 1.9
	add_child(_fire)
	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = Color(1.0, 0.45, 0.15)
	_light.energy = 0.0
	_light.texture_scale = length / 60.0
	_light.position = Vector2(length * 0.45, 0)
	add_child(_light)


func start() -> void:
	active = true
	_tick = 0.0


func stop() -> void:
	active = false


func _process(delta: float) -> void:
	_light.energy = move_toward(_light.energy, 1.8 if active else 0.0, delta * 8.0)
	if not active:
		return
	# speed and drag tuned so the jet reaches about `length`
	var speed := length * 3.0
	var origin := global_position
	var dir := Vector2.from_angle(global_rotation)
	_spawn += flame_rate * delta
	while _spawn >= 1.0:
		_spawn -= 1.0
		var a := randf_range(-half_angle, half_angle) * 0.75
		var v := dir.rotated(a) * speed * randf_range(0.8, 1.05)
		var life := randf_range(0.4, 0.6)
		_fire.emit(origin + dir * randf_range(0.0, 8.0), v, randf_range(flame_size.x, flame_size.y), life)
		if randf() < 0.3:
			# white-hot core right at the mouth
			_fire.emit(origin, dir.rotated(a * 0.3) * speed * 0.6, flame_size.x, 0.1)
		if randf() < 0.12:
			_soot.emit(origin + dir * length * randf_range(0.5, 0.9), dir * 60.0 + Vector2(0, -40),
				flame_size.y * randf_range(0.9, 1.4), randf_range(0.8, 1.4))


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
