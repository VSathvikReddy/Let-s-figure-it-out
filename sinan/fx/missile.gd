extends Node2D
## The rocket. Accelerates along a slightly drooping arc, leaves fire/smoke/spark
## trails, flickers a light, and explodes where a ray sweep hits the frame.

const FxLib := preload("res://sinan/fx/fx_lib.gd")
const Explosion := preload("res://sinan/fx/explosion.gd")
const DepthFlight := preload("res://sinan/fx/depth_flight.gd")

const START_SPEED := 520.0
const MAX_SPEED := 1500.0
const ACCEL := 1800.0
const GRAVITY := 380.0
const MAX_LIFE := 4.0
const BLAST_RADIUS := 130.0
const PAINT_SHAKE := 0.6  # screen shake for a painting hit

var vel := Vector2.ZERO
var shooter: CollisionObject2D

var _age := 0.0
var _last_pos := Vector2.ZERO
var _exploded := false
var _light: PointLight2D
var _trails: Array[CPUParticles2D] = []
var _flight: DepthFlight  # set when fired into the painting
var _paint_radius := 70.0
var _paint_strength := 1.0


## Call BEFORE adding to the tree so the trails start at the muzzle, not the origin.
func launch(parent: Node, from: Vector2, dir: Vector2, who: CollisionObject2D, check_from: Vector2) -> void:
	position = FxLib.to_parent_space(parent, from)
	_last_pos = check_from
	vel = dir * START_SPEED
	rotation = dir.angle()
	shooter = who


## Fire into the painting (Wild Guns style). pick comes from paint_picker.
## Call BEFORE adding to the tree.
## arc / impact_radius / strength come from the weapon's inspector settings.
func launch_into_painting(parent: Node, from: Vector2, pick: Dictionary, world_target: Vector2,
		arc: float, impact_radius: float, strength: float) -> void:
	position = FxLib.to_parent_space(parent, from)
	var s: float = pick.get("scale", 0.3)
	_flight = DepthFlight.new(self, from, pick, world_target, lerpf(0.75, 0.45, s), arc)
	_paint_radius = impact_radius
	_paint_strength = strength


func _ready() -> void:
	z_index = 0 if _flight else 3

	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = Color(1.0, 0.62, 0.28)
	_light.energy = 1.6
	_light.texture_scale = 2.8
	add_child(_light)

	_add_trail({
		"one_shot": false, "amount": 28, "life": 0.3, "v_min": 40.0, "v_max": 130.0,
		"spread": 14.0, "direction": Vector2.LEFT, "s_min": 0.25, "s_max": 0.55,
		"additive": true,
	}, Vector2(-12, 0))
	_add_trail({
		"one_shot": false, "amount": 50, "life": 1.1, "v_min": 8.0, "v_max": 45.0,
		"spread": 22.0, "direction": Vector2.LEFT, "ramp": FxLib.smoke_ramp(),
		"s_min": 0.3, "s_max": 0.65, "curve": FxLib.grow(),
		"gravity": Vector2(0, -25),
	}, Vector2(-15, 0))
	_add_trail({
		"one_shot": false, "amount": 14, "life": 0.4, "v_min": 60.0, "v_max": 230.0,
		"spread": 30.0, "direction": Vector2.LEFT, "texture": FxLib.streak(),
		"align": true, "angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0,
		"spin_max": 0.0, "s_min": 0.3, "s_max": 0.7, "additive": true,
		"ramp": FxLib.spark_ramp(), "gravity": Vector2(0, 180),
	}, Vector2(-12, 0))


func _add_trail(opts: Dictionary, at: Vector2) -> void:
	var p := FxLib.emitter(opts)
	p.position = at
	add_child(p)
	_trails.append(p)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_age += delta

	if _flight:
		if _flight.step(delta):
			explode()
		return

	vel += Vector2(0.0, GRAVITY) * delta
	vel += vel.normalized() * ACCEL * delta
	vel = vel.limit_length(MAX_SPEED)

	var next := global_position + vel * delta
	var ex: Array[RID] = []
	if shooter:
		ex.append(shooter.get_rid())
	var q := PhysicsRayQueryParameters2D.create(_last_pos, next, 1, ex)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		explode()
		return

	global_position = next
	_last_pos = next
	rotation = vel.angle()

	if _age > MAX_LIFE or global_position.y > 3000.0:
		explode()


func _process(delta: float) -> void:
	if _exploded:
		return
	_light.energy = 1.3 + randf() * 0.6
	queue_redraw()


## Painting hits keep the full blast, shake and hit-stop; only the player
## knockback is skipped (the blast is inside the painting, not next to you).
func explode() -> void:
	if _exploded:
		return
	_exploded = true
	var pos := global_position
	var world := get_parent()

	# Let the trails burn out on their own instead of vanishing with the rocket.
	for t in _trails:
		t.emitting = false
		t.reparent(world)
		get_tree().create_timer(1.6).timeout.connect(t.queue_free)

	# Position must be set before add_child: the explosion spawns its effects in _ready().
	# Painting hits live inside the hit Parallax2D layer so they scroll with it.
	var fx_parent := world
	if _flight and is_instance_valid(_flight.layer):
		fx_parent = _flight.layer
	var fx := Explosion.new()
	fx.radius = BLAST_RADIUS
	fx.in_painting = _flight != null
	fx.position = FxLib.to_parent_space(fx_parent, pos)
	fx_parent.add_child(fx)

	if _flight:
		# Hook for the painting (M2/M3): restore/damage around the hit, in layer space.
		get_tree().call_group("painting", "on_paint_hit", _flight.layer, _flight.local, _paint_radius, _paint_strength)
		get_tree().call_group("player", "add_trauma", PAINT_SHAKE)
	else:
		get_tree().call_group("player", "on_explosion", pos, BLAST_RADIUS)

	# Brief hit-stop; the timer ignores time_scale so it always restores.
	Engine.time_scale = 0.08
	get_tree().create_timer(0.07, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)

	queue_free()


func _draw() -> void:
	# Jiggle: tiny perpendicular wobble, roll, and a pop-in scale on launch.
	var pop := 1.0 + maxf(0.0, 1.0 - _age / 0.18) * 0.7
	var wob := sin(_age * 55.0) * 0.9
	draw_set_transform(Vector2(0.0, wob), sin(_age * 38.0) * 0.05, Vector2(pop, pop))

	var fl := 9.0 + randf() * 7.0
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -3.4), Vector2(-10 - fl, 0), Vector2(-10, 3.4)]), Color(1.0, 0.5, 0.1, 0.9))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -1.8), Vector2(-10 - fl * 0.55, 0), Vector2(-10, 1.8)]), Color(1.0, 0.95, 0.6))

	var fin := Color(0.55, 0.12, 0.1)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -3.2), Vector2(-13, -8.5), Vector2(-10, -3.2)]), fin)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, 3.2), Vector2(-13, 8.5), Vector2(-10, 3.2)]), fin)

	draw_rect(Rect2(-10, -3.2, 18, 6.4), Color(0.86, 0.86, 0.9))
	draw_rect(Rect2(-3, -3.2, 4, 6.4), Color(0.8, 0.15, 0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(8, -3.2), Vector2(15.5, 0), Vector2(8, 3.2)]), Color(0.85, 0.15, 0.12))
	draw_line(Vector2(-10, -1.8), Vector2(8, -1.8), Color(1, 1, 1, 0.55), 1.0)
