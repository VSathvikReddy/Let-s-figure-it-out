extends Node2D
## Magic orb. Lobbed with gravity in the studio (bounces, then settles), or flown
## into the painting. Once landed it charges for fuse_time, then bursts with
## orb_blast and RESTORES the painting around it. All tuning comes from the
## orb staff weapon's inspector (copied in by orb_staff.gd before launch).

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const DepthFlight := preload("res://sinan/painting/depth_flight.gd")
const OrbBlast := preload("res://sinan/fx/blasts/orb_blast.gd")

enum State { FLYING, CHARGING }

# --- set by the weapon
var throw_speed := 900.0
var gravity := 1600.0
var bounces := 1
var bounce_damping := 0.4
var fuse_time := 2.0
var max_flight_time := 3.0
var orb_radius := 9.0
var core_color := Color(0.9, 1.0, 1.0)
var glow_color := Color(0.35, 0.85, 1.0)
var trail_color := Color(0.6, 0.95, 1.0)
var blast_color := Color(1.0, 0.9, 0.55)
var light_energy := 1.4
var blast_radius := 120.0
var blast_shake := 0.15
var restore_radius := 80.0
var restore_strength := 1.0
## Damage to enemies when it bursts in the world (set by the staff).
var damage := 0.0

var vel := Vector2.ZERO
var shooter: CollisionObject2D

var _state := State.FLYING
var _age := 0.0
var _t := 0.0  # time spent charging
var _last_pos := Vector2.ZERO
var _bounces_left := 0
var _rest_normal := Vector2.UP  # surface it settled on; ZERO = flat on the canvas
var _flight: DepthFlight
var _light: PointLight2D
var _trails: Array[CPUParticles2D] = []
var _charge: CPUParticles2D


## Call BEFORE adding to the tree.
func launch(parent: Node, from: Vector2, dir: Vector2, who: CollisionObject2D, check_from: Vector2) -> void:
	position = FxLib.to_parent_space(parent, from)
	_last_pos = check_from
	vel = dir * throw_speed
	shooter = who
	_bounces_left = bounces


## Fly into the painting and charge there. Call BEFORE adding to the tree.
func launch_into_painting(parent: Node, from: Vector2, pick: Dictionary, world_target: Vector2, arc: float) -> void:
	position = FxLib.to_parent_space(parent, from)
	var s: float = pick.get("scale", 0.3)
	_flight = DepthFlight.new(self, from, pick, world_target, lerpf(0.7, 0.45, s), arc)


func _ready() -> void:
	z_index = 0 if _flight else 3
	material = FxLib.additive()

	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = glow_color
	_light.energy = light_energy
	_light.texture_scale = orb_radius / 4.0
	add_child(_light)
	_setup_fx()


# ---------------------------------------------------------------- look hooks
# Override these in a subclass to restyle the orb (see paint_blob.gd).

## Create the flight trails (append to _trails) and the _charge emitter.
func _setup_fx() -> void:
	# glowing trail + a few falling glitter sparks
	_trails.append(_child_emitter({
		"one_shot": false, "amount": 40, "life": 0.6, "v_min": 5.0, "v_max": 25.0,
		"texture": FxLib.glow(), "s_min": orb_radius / 64.0, "s_max": orb_radius / 32.0,
		"ramp": FxLib.fade_ramp(trail_color), "additive": true, "gravity": Vector2(0, -20),
	}))
	_trails.append(_child_emitter({
		"one_shot": false, "amount": 12, "life": 0.7, "v_min": 20.0, "v_max": 70.0,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.2, "s_max": 0.4,
		"ramp": FxLib.fade_ramp(core_color), "additive": true, "gravity": Vector2(0, 160),
	}))
	# charge-up: sparkles drawn inwards while waiting (moves with the orb)
	_charge = _child_emitter({
		"one_shot": false, "amount": 26, "life": 0.5, "v_min": 0.0, "v_max": 0.0,
		"emit_radius": orb_radius * 5.0, "radial_min": -420.0, "radial_max": -300.0,
		"texture": FxLib.glow(), "s_min": orb_radius / 110.0, "s_max": orb_radius / 60.0,
		"ramp": FxLib.fade_ramp(glow_color), "additive": true, "curve": null,
	})
	_charge.local_coords = true
	_charge.emitting = false


## Effect when it settles (start of charging).
func _on_land_fx() -> void:
	_sparkle_puff(10)


## The burst visuals, added to `parent` at this orb's position.
func _spawn_burst(parent: Node) -> void:
	var b := OrbBlast.new()
	b.radius = blast_radius
	b.color = blast_color
	b.glow = glow_color
	b.light_energy = light_energy * 2.2
	b.position = position
	parent.add_child(b)


# ---------------------------------------------------------------- behaviour

func _child_emitter(opts: Dictionary) -> CPUParticles2D:
	var p := FxLib.emitter(opts)
	add_child(p)
	return p


func _physics_process(delta: float) -> void:
	_age += delta
	match _state:
		State.FLYING:
			if _flight:
				if _flight.step(delta):
					_land_in_painting()
				return
			_fly(delta)
		State.CHARGING:
			_t += delta
			if _t >= fuse_time:
				_burst()


func _fly(delta: float) -> void:
	vel.y += gravity * delta
	var next := global_position + vel * delta
	var ex: Array[RID] = []
	if shooter:
		ex.append(shooter.get_rid())
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(_last_pos, next, 1, ex))
	if not hit.is_empty():
		var n: Vector2 = hit.normal if hit.normal != Vector2.ZERO else Vector2.UP
		global_position = hit.position + n * orb_radius
		_last_pos = global_position
		if _bounces_left > 0 and vel.length() > 250.0:
			_bounces_left -= 1
			vel = vel.bounce(n) * bounce_damping
			_sparkle_puff(6)
		else:
			_rest_normal = n
			_land()
		return
	global_position = next
	_last_pos = next
	if _age > max_flight_time:
		_land()


func _land_in_painting() -> void:
	# Live inside the hit layer so it scrolls with the parallax while charging.
	if is_instance_valid(_flight.layer):
		reparent(_flight.layer)
	_rest_normal = Vector2.ZERO  # flat on the canvas
	_land()


func _land() -> void:
	_state = State.CHARGING
	_t = 0.0
	vel = Vector2.ZERO
	_charge.emitting = true
	for t in _trails:
		t.emitting = false
	_on_land_fx()


func _sparkle_puff(amount: int) -> void:
	FxLib.burst(get_parent(), {
		"amount": amount, "life": 0.4, "v_min": 60.0, "v_max": 180.0,
		"texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.12, "damp_min": 200.0, "damp_max": 300.0,
		"ramp": FxLib.fade_ramp(glow_color), "additive": true, "curve": null,
	}, global_position)


func _burst() -> void:
	var parent := get_parent()
	_spawn_burst(parent)

	# Restore = a negative stamp on the distortion mask. Only shots fired INTO
	# the painting touch it; studio (foreground) bursts are purely visual.
	if _flight and is_instance_valid(_flight.layer):
		Paint.hit(self, _flight.layer, _flight.local, restore_radius, -restore_strength, Paint.Kind.RESTORE, &"orb")
		get_tree().call_group("ghosts", "on_painting_shot", _flight.layer, _flight.local, restore_radius)
	elif damage > 0.0:
		# in the world the burst hurts enemies like a small blast
		get_tree().call_group("enemies", "on_explosion_damage", global_position, blast_radius * 0.8, damage)
		get_tree().call_group("smoke_vents", "on_explosion_damage", global_position, blast_radius * 0.8, damage)
	get_tree().call_group("player", "add_trauma", blast_shake, global_position)

	for t in _trails:
		t.reparent(parent)
		get_tree().create_timer(1.0).timeout.connect(t.queue_free)
	queue_free()


func _process(_delta: float) -> void:
	var k := _t / fuse_time if _state == State.CHARGING else 0.0
	_light.energy = light_energy * (1.0 + 0.3 * sin(_age * lerpf(6.0, 30.0, k)) + k)
	queue_redraw()


func _draw() -> void:
	var charging := _state == State.CHARGING
	var k := clampf(_t / fuse_time, 0.0, 1.0) if charging else 0.0
	var pulse := 0.5 + 0.5 * sin(_age * lerpf(6.0, 30.0, k))  # pulses faster near the burst
	var r := orb_radius * (1.0 + 0.15 * pulse + 0.35 * k)
	var bob := Vector2(0.0, sin(_age * 3.0) * 2.0) if charging else Vector2.ZERO

	draw_circle(bob, r * 3.2, Color(glow_color, 0.07))
	draw_circle(bob, r * 2.0, Color(glow_color, 0.18))
	draw_circle(bob, r * 1.25, Color(glow_color, 0.5))
	draw_circle(bob, r, core_color)
	draw_circle(bob + Vector2(-r, -r) * 0.3, r * 0.3, Color(1, 1, 1, 0.8))

	# little motes orbiting on a tilted ellipse
	for i in 3:
		var a := _age * (4.0 + 6.0 * k) + i * TAU / 3.0
		var p := Vector2(cos(a) * r * 2.0, sin(a) * r * 0.8)
		draw_circle(bob + p, r * 0.22, Color(core_color, 0.9))

	# countdown ring while charging
	if charging:
		draw_arc(bob, r * 3.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - k), 48, Color(glow_color, 0.7), 1.5, true)
