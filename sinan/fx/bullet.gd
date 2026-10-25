extends Node2D
## Pistol bullet: fast, straight, glowing tracer. Small spark impact — no blast,
## no knockback, no hit-stop. In the painting it stamps a small distortion.

const FxLib := preload("res://sinan/fx/fx_lib.gd")
const DepthFlight := preload("res://sinan/fx/depth_flight.gd")

const SPEED := 2200.0
const MAX_LIFE := 0.9
const TRACER := 60.0

var vel := Vector2.ZERO
var shooter: CollisionObject2D

var _age := 0.0
var _last_pos := Vector2.ZERO
var _light: PointLight2D
var _flight: DepthFlight  # set when fired into the painting
var _paint_radius := 25.0
var _paint_strength := 0.7


## Call BEFORE adding to the tree (same reason as missile.launch).
func launch(parent: Node, from: Vector2, dir: Vector2, who: CollisionObject2D, check_from: Vector2) -> void:
	position = FxLib.to_parent_space(parent, from)
	_last_pos = check_from
	vel = dir * SPEED
	rotation = dir.angle()
	shooter = who


## Fire into the painting: shrinks with the target layer's depth. Call BEFORE add_child.
## arc / impact_radius / strength come from the weapon's inspector settings.
func launch_into_painting(parent: Node, from: Vector2, pick: Dictionary, world_target: Vector2,
		arc: float, impact_radius: float, strength: float) -> void:
	position = FxLib.to_parent_space(parent, from)
	var s: float = pick.get("scale", 0.3)
	_flight = DepthFlight.new(self, from, pick, world_target, lerpf(0.32, 0.18, s), arc)
	_paint_radius = impact_radius
	_paint_strength = strength
	_age = 1.0  # full-length tracer from the start


func _ready() -> void:
	z_index = 0 if _flight else 3
	material = FxLib.additive()
	_light = PointLight2D.new()
	_light.texture = FxLib.glow()
	_light.color = Color(1.0, 0.8, 0.45)
	_light.energy = 0.7
	_light.texture_scale = 1.0
	add_child(_light)


func _physics_process(delta: float) -> void:
	_age += delta
	if _flight:
		if _flight.step(delta):
			# Spawn inside the hit layer so the sparks scroll with the parallax.
			var fx_parent: Node = _flight.layer if is_instance_valid(_flight.layer) else get_parent()
			FxLib.impact_small(fx_parent, global_position, Vector2.UP.rotated(randf_range(-0.8, 0.8)))
			get_tree().call_group("painting", "on_paint_hit", _flight.layer, _flight.local, _paint_radius, _paint_strength)
			get_tree().call_group("player", "add_trauma", 0.05)
			queue_free()
		return
	var next := global_position + vel * delta
	var ex: Array[RID] = []
	if shooter:
		ex.append(shooter.get_rid())
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(_last_pos, next, 1, ex))
	if not hit.is_empty():
		var n: Vector2 = hit.normal
		if n == Vector2.ZERO:
			n = -vel.normalized()
		FxLib.impact_small(get_parent(), hit.position, n)
		get_tree().call_group("player", "add_trauma", 0.05)
		queue_free()
		return
	global_position = next
	_last_pos = next
	if _age > MAX_LIFE:
		queue_free()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var tail := minf(_age * SPEED, TRACER)
	draw_line(Vector2(-tail, 0), Vector2.ZERO, Color(1.0, 0.6, 0.2, 0.35), 5.0)
	draw_line(Vector2(-tail, 0), Vector2.ZERO, Color(1.0, 0.92, 0.65, 1.0), 2.0)
	draw_circle(Vector2.ZERO, 2.2, Color(1, 1, 0.9))
