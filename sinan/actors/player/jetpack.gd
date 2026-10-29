extends Node2D
## Jetpack (skill tree: Special branch) - the team's jetpack (player/player.gd),
## same controls, same numbers, same look:
##   hold W / Up to thrust up, A / D push sideways; not thrusting = heavy
##   gravity; drag slows every direction; speeds are capped; the body tilts
##   up to 12 degrees with A / D; two thrusters on the body and a fire trail.
## While you are in the air after thrusting, the player moves with these
## physics (fly()); on the ground it is the normal player again.
## On top of the team's version: a fuel tank (refills on the ground) and the
## skill-tree upgrades - jet_thrust (up thrust), jet_control (sideways thrust
## and speed), jet_stability (climb speed), jet_fuel, jet_refuel, jet_hover
## (less fuel when only going up), jet_boost (Shift while flying).

const THRUSTER_TEX := preload("res://sinan/assets/jetpack/thruster.png")
const PARTICLE_TEX := preload("res://sinan/assets/jetpack/flame_particle.png")

@export_group("Thruster Forces")
@export var horizontal_thrust: float = 600.0
@export var up_thrust: float = 800.0

@export_group("Limits & Gravity")
@export var max_horizontal_speed: float = 250.0
@export var max_rise_speed: float = 300.0
@export var max_fall_speed: float = 400.0     ## Fast terminal fall velocity
@export var fast_gravity: float = 900.0       ## Strong gravity pulling downward
@export var passive_drag: float = 1.8         ## Opposes motion in all directions

@export_group("Visual FX")
@export var max_tilt_angle_deg: float = 12.0
@export var tilt_speed: float = 8.0

@export_group("Fuel")
## Seconds of thrust on a full tank (0 = endless, like the team's version).
@export var fuel_seconds := 3.0
## Tanks refilled per second on the ground.
@export var refuel_rate := 0.8

@export_group("Afterburner")
@export var boost_speed := 450.0

var flying := false      # the jetpack physics are moving the player (thrusting, or falling after it)
var thrusting := false
var fuel := 1.0
var _boosts := 0
var _player: CharacterBody2D
var _left_jet: Sprite2D
var _right_jet: Sprite2D
var _left_fire: GPUParticles2D
var _right_fire: GPUParticles2D


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	z_index = 1
	_build_visuals.call_deferred()


func unlocked() -> bool:
	return Progress.stat(&"unlock_jetpack") > 0.0


func refill() -> void:
	fuel = 1.0
	_boosts = int(Progress.stat(&"jet_boost"))
	flying = false
	thrusting = false
	_show(false)


## Every physics step, before the player moves. Returns `flying`.
func update(delta: float, on_floor: bool, dir_x: float) -> bool:
	if not unlocked():
		flying = false
		thrusting = false
		_show(false)
		return false
	if on_floor:
		fuel = minf(1.0, fuel + refuel_rate * (1.0 + Progress.stat(&"jet_refuel")) * delta)
		_boosts = int(Progress.stat(&"jet_boost"))
	thrusting = Input.is_action_pressed("jet") and (fuel > 0.0 or fuel_seconds <= 0.0)
	if thrusting and fuel_seconds > 0.0:
		var drain := 1.0 / (fuel_seconds * (1.0 + Progress.stat(&"jet_fuel")))
		if dir_x == 0.0:
			drain *= maxf(0.2, 1.0 - Progress.stat(&"jet_hover"))
		fuel = maxf(0.0, fuel - drain * delta)
	if thrusting:
		flying = true
	elif on_floor:
		flying = false
	_show(thrusting)
	queue_redraw()
	return flying


## The team's jetpack physics: the player's velocity after one step.
func fly(v: Vector2, dir_x: float, delta: float) -> Vector2:
	var control := 1.0 + Progress.stat(&"jet_control")
	# 1-2. thrust sideways and up, or heavy gravity when not thrusting
	if dir_x != 0.0:
		v.x += dir_x * horizontal_thrust * control * delta
	if thrusting:
		v.y -= up_thrust * (1.0 + Progress.stat(&"jet_thrust")) * delta
	else:
		v.y += fast_gravity * delta
	# 3. passive drag (opposes all motion)
	v.x = move_toward(v.x, 0.0, absf(v.x) * passive_drag * delta)
	v.y = move_toward(v.y, 0.0, absf(v.y) * passive_drag * delta)
	# 4. terminal velocity caps
	var side := max_horizontal_speed * control
	v.x = clampf(v.x, -side, side)
	v.y = clampf(v.y, -max_rise_speed * (1.0 + Progress.stat(&"jet_stability")), max_fall_speed)
	return v


## The body's tilt while flying (radians) - the team's sprite tilt.
func tilt_target(dir_x: float) -> float:
	return deg_to_rad(dir_x * max_tilt_angle_deg)


## Afterburner (Shift while flying): a burst upward and sideways. False if none left.
func try_boost(dir_x: float) -> bool:
	if not flying or _boosts <= 0:
		return false
	_boosts -= 1
	_player.velocity += Vector2(dir_x * 0.6, -1.0).normalized() * boost_speed
	_player.add_trauma(0.12)
	return true


func _show(on: bool) -> void:
	if _left_jet == null:
		return
	_left_jet.visible = on
	_right_jet.visible = on
	_left_fire.emitting = on
	_right_fire.emitting = on


## The team's two thrusters (player.tscn: leftthrust / rightthrust) and their
## fire trails (leftparti / rightparti), on the player's body so they tilt and
## flip with it. Their body is 64 px; this rig is 128 units, so positions and
## sizes are doubled from their sprite space.
func _build_visuals() -> void:
	var body: Node2D = _player.get_node_or_null("Visual/Body")
	if body == null:
		return
	_left_jet = _thruster(body, Vector2(-14, 26), 2.864759, Vector2(0.316, 0.244))
	_right_jet = _thruster(body, Vector2(14, 26), 2.87962, Vector2(0.306, 0.244))
	var mat := _fire_material()
	_left_fire = _fire(body, Vector2(-15, 64), mat)
	_right_fire = _fire(body, Vector2(15, 62), mat)
	_show(false)


func _thruster(body: Node2D, at: Vector2, rot: float, scl: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = THRUSTER_TEX
	s.show_behind_parent = true
	s.z_index = -1
	s.position = at
	s.rotation = rot
	s.scale = scl
	body.add_child(s)
	return s


func _fire(body: Node2D, at: Vector2, mat: ParticleProcessMaterial) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.position = at
	p.emitting = false
	p.amount = 70
	p.texture = PARTICLE_TEX
	p.lifetime = 0.4
	p.process_material = mat
	p.show_behind_parent = true
	p.z_index = -1
	body.add_child(p)
	return p


## Exactly the team's ParticleProcessMaterial.
func _fire_material() -> ParticleProcessMaterial:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0, 0.2, 0.6, 0.8, 1])
	grad.colors = PackedColorArray([Color(1, 0.9098039, 0, 1), Color(1, 0.68235296, 0, 1), Color(0.6, 0, 0, 1),
		Color(0.12005126, 0.12005126, 0.12005126, 1), Color(0, 0, 0, 1)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.8101852, 0.6875))
	curve.add_point(Vector2(1, 0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve
	var m := ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	m.direction = Vector3(0, 1, 0)
	m.spread = 15.565
	m.initial_velocity_min = 200.0
	m.initial_velocity_max = 350.0
	m.gravity = Vector3(0, 98, 0)
	m.linear_accel_min = -100.0
	m.linear_accel_max = -100.0
	m.scale_curve = scale_tex
	m.color_ramp = ramp
	return m


## Fuel gauge above the head (only while it is not full).
func _draw() -> void:
	if not unlocked() or fuel_seconds <= 0.0 or fuel >= 0.999:
		return
	var r := Rect2(-28, -96, 56, 6)
	draw_rect(r.grow(1.5), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * fuel, r.size.y)), Color(1.0, 0.75, 0.3) if fuel > 0.25 else Color(1.0, 0.35, 0.25))
