extends Node2D
## The witch's homing orb, in the spirit of the Radiance's orbs (Hollow Knight):
## it appears beside her, swells and charges, then slowly accelerates toward the
## player with limited steering. It is slower than the player and turns wide, so
## a well-timed dash or jump makes it overshoot. When its lifetime runs out it
## swells and detonates in a small damaging hex blast.
## All values are set by the witch ("Homing Orbs" group on witch.gd).

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const HexBlast := preload("res://sinan/fx/blasts/hex_blast.gd")

enum State { CHARGE, CHASE, FADE }

var charge_time := 0.6
var max_speed := 230.0
var steering := 260.0          # max change of velocity per second (lower = wider turns)
var lifetime := 4.5             # seconds of chasing before it detonates
var end_explosion_radius := 45.0  # damage radius of the detonation
var end_explosion_damage := 1.0
var damage := 1.0
var hit_radius := 12.0
var pass_through_walls := true
var orb_radius := 9.0
var orb_color := Color(0.75, 0.3, 1.0)
var core_color := Color(1.0, 0.9, 1.0)
var target                      # the player node
var shooter                      # the witch that fired it (the death camera looks at it)
var shooter_rid := RID()

var vel := Vector2.ZERO
var _state := State.CHARGE
var _t := 0.0
var _age := 0.0
var _trail: CPUParticles2D
var _light: PointLight2D


func _ready() -> void:
	z_index = 3
	material = FxLib.additive()
	scale = Vector2.ZERO
	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = orb_color
	_light.energy = 0.0
	_light.texture_scale = orb_radius / 5.0
	add_child(_light)
	_trail = FxLib.emitter({
		"one_shot": false, "amount": 26, "life": 0.5, "v_min": 5.0, "v_max": 25.0,
		"texture": FxLib.glow(), "s_min": orb_radius / 160.0, "s_max": orb_radius / 80.0,
		"ramp": FxLib.fade_ramp(orb_color), "additive": true, "curve": null,
	})
	_trail.emitting = false
	add_child(_trail)
	# charge-up: light pulled into the orb as it forms
	FxLib.burst(get_parent(), {
		"amount": 14, "life": charge_time * 0.8, "explosiveness": 0.4, "v_min": 0.0, "v_max": 0.0,
		"emit_radius": orb_radius * 4.0, "radial_min": -200.0, "radial_max": -140.0,
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.08,
		"ramp": FxLib.fade_ramp(orb_color), "additive": true, "curve": null,
	}, global_position)


func _physics_process(delta: float) -> void:
	_t += delta
	_age += delta
	match _state:
		State.CHARGE:
			var k := clampf(_t / charge_time, 0.0, 1.0)
			scale = Vector2.ONE * (1.0 - pow(1.0 - k, 3.0))
			position.y -= 6.0 * delta  # floats up a touch while forming
			if k >= 1.0:
				_state = State.CHASE
				_t = 0.0
				_trail.emitting = true
				if is_instance_valid(target):
					vel = (target.global_position - global_position).normalized() * max_speed * 0.15
		State.CHASE:
			if is_instance_valid(target):
				var desired: Vector2 = (target.global_position - global_position).normalized() * max_speed
				vel += (desired - vel).limit_length(steering * delta)
			var next := global_position + vel * delta
			if not pass_through_walls:
				var ex: Array[RID] = [shooter_rid]
				var hit := get_world_2d().direct_space_state.intersect_ray(
					PhysicsRayQueryParameters2D.create(global_position, next, 1, ex))
				if not hit.is_empty() and hit.collider != target:
					global_position = hit.position
					_burst(false)
					return
			global_position = next
			if is_instance_valid(target) and global_position.distance_to(target.global_position as Vector2) <= hit_radius + 12.0:
				if target.has_method("take_damage"):
					target.take_damage(damage, global_position, -1.0, false, shooter)
				_burst(true)
				return
			if _t >= lifetime:
				_state = State.FADE
				_t = 0.0
				_trail.emitting = false
		State.FADE:
			# stalls, swells and flickers... then detonates
			vel *= 0.9
			global_position += vel * delta
			scale = Vector2.ONE * (1.0 + 0.5 * clampf(_t / 0.35, 0.0, 1.0)) * (1.0 + 0.12 * sin(_t * 60.0))
			if _t >= 0.35:
				_detonate()


func _burst(hit_player: bool) -> void:
	_hex_blast(orb_radius * (5.0 if hit_player else 3.5))
	queue_free()


## End of lifetime: small explosion that hurts the player if they are close.
func _detonate() -> void:
	if is_instance_valid(target) and target.has_method("take_damage") 			and global_position.distance_to(target.global_position as Vector2) <= end_explosion_radius:
		target.take_damage(end_explosion_damage, global_position, -1.0, false, shooter)
	_hex_blast(end_explosion_radius)
	get_tree().call_group("player", "add_trauma", 0.12, global_position)
	queue_free()


func _hex_blast(r: float) -> void:
	var parent := get_parent()
	var b := HexBlast.new()
	b.radius = r
	b.color = orb_color
	b.core_color = core_color
	b.position = position
	parent.add_child(b)
	_trail.emitting = false
	_trail.reparent(parent)
	get_tree().create_timer(0.6).timeout.connect(_trail.queue_free)


func _process(_delta: float) -> void:
	var charging := _state == State.CHARGE
	_light.energy = (0.6 if charging else 1.2) * scale.x + 0.3 * sin(_age * 20.0)
	queue_redraw()


func _draw() -> void:
	var r := orb_radius * (1.0 + 0.1 * sin(_age * 18.0))
	var charging := _state == State.CHARGE
	# soft halo
	draw_circle(Vector2.ZERO, r * 3.2, Color(orb_color, 0.08))
	draw_circle(Vector2.ZERO, r * 2.0, Color(orb_color, 0.25))
	# flickering light rays, spinning (brighter while forming so the threat reads)
	var rays := 8
	for i in rays:
		var a := _age * 2.5 + i * TAU / rays
		var flick := 0.6 + 0.4 * sin(_age * 23.0 + i * 1.7)
		var ray_len := r * (2.2 + (1.2 if charging else 0.6) * flick)
		draw_line(Vector2.from_angle(a) * r * 1.1, Vector2.from_angle(a) * ray_len, Color(core_color, 0.35 * flick), 1.5, true)
	draw_circle(Vector2.ZERO, r * 1.25, Color(orb_color, 0.6))
	draw_circle(Vector2.ZERO, r, core_color)
	draw_circle(Vector2.ZERO, r * 0.55, Color(1, 1, 1, 1))
