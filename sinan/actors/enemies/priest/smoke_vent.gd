extends StaticBody2D
## The priest's smoke orb after it lands: a smouldering censer ball that
## keeps pouring out smoke. The puffs spread sideways and slowly rise, so the
## area fills up over a few seconds; when the vent runs dry the smoke lifts
## away on its own. Shoot it (it is on the enemy layer, bullets hit it) and it
## cracks open - its smoke clears quickly.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const SmokeManager := preload("res://sinan/actors/enemies/priest/smoke_manager.gd")

static var _next_id := 1

@export var emit_time := 9.0
@export var puffs_per_second := 9.0
@export var puff_size := Vector2(45, 75)
@export var puff_life := Vector2(7.0, 10.0)
@export var spread_speed := Vector2(25, 75)
@export var health := 1.0
@export var shell_color := Color(0.2, 0.17, 0.19)
@export var ember_color := Color(1.0, 0.55, 0.2)
## Hangs where it is (painting sequences) instead of dropping to the ground.
@export var floating := false

var vent_id := 0
var _t := 0.0
var _emit := 0.0
var _dead := false
var _manager: Node2D
var _fall := 0.0
var _landed := false
var _fall_exclude: Array[RID] = []


func _ready() -> void:
	vent_id = _next_id
	_next_id += 1
	add_to_group("smoke_vents")
	collision_layer = 2
	collision_mask = 0
	z_index = 3
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 14.0
	cs.shape = c
	add_child(cs)
	_manager = SmokeManager.get_for(self)
	# landing puff
	for i in 6:
		_puff(randf_range(0.6, 1.4))


func _physics_process(delta: float) -> void:
	if floating or _landed:
		return
	# drops onto whatever is below (boards or the floor) and rolls to a stop
	_fall += 900.0 * delta
	var step := Vector2(0, _fall * delta)
	if _fall_exclude.is_empty():
		_fall_exclude.append(get_rid())
		var pl := get_tree().get_first_node_in_group("player")
		if pl is CollisionObject2D:
			_fall_exclude.append((pl as CollisionObject2D).get_rid())
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(global_position, global_position + step + Vector2(0, 11), 1, _fall_exclude))
	if hit.is_empty():
		global_position += step
		NavGraph.keep_above_ground(self, 11.0)
	else:
		global_position = hit.position - Vector2(0, 11)
		_landed = true
		FxLib.burst(get_parent(), {
			"amount": 6, "life": 0.4, "v_min": 40.0, "v_max": 110.0, "direction": Vector2.UP, "spread": 70.0,
			"ramp": FxLib.dust_ramp(), "s_min": 0.12, "s_max": 0.25,
		}, global_position + Vector2(0, 10))


func _process(delta: float) -> void:
	_t += delta
	if not _dead and _t < emit_time:
		# pours hardest at first, then tapers
		_emit += puffs_per_second * lerpf(1.4, 0.6, _t / emit_time) * delta
		while _emit >= 1.0:
			_emit -= 1.0
			_puff(1.0)
	elif not _dead and _t >= emit_time:
		_dead = true
		collision_layer = 0
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 1.5)
		tw.tween_callback(queue_free)
	queue_redraw()


func _puff(strength: float) -> void:
	var side := -1.0 if randf() < 0.5 else 1.0
	var vel := Vector2(side * randf_range(spread_speed.x, spread_speed.y) * strength, randf_range(-30.0, -8.0))
	_manager.add_puff(global_position + Vector2(randf_range(-6, 6), -6), vel,
		randf_range(puff_size.x, puff_size.y), randf_range(puff_life.x, puff_life.y), vent_id)


## Bullets and the machete.
func take_hit(amount: float, _from_pos: Vector2, _info := {}) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_break()


func on_explosion_damage(pos: Vector2, radius: float, _damage: float) -> void:
	if global_position.distance_to(pos) <= radius * 1.4:
		_break()


func _break() -> void:
	if _dead:
		return
	_dead = true
	collision_layer = 0
	_manager.clear_vent(vent_id)
	var world := get_parent()
	FxLib.burst(world, {
		"amount": 14, "life": 0.5, "v_min": 120.0, "v_max": 300.0, "gravity": Vector2(0, 500),
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.09,
		"ramp": FxLib.fade_ramp(ember_color), "additive": true, "curve": null,
	}, global_position)
	FxLib.smoke_burst(world, global_position, 0.5, shell_color, 8)
	FxLib.flash_light(world, global_position, ember_color, 1.5, 1.0, 0.2)
	get_tree().call_group("player", "add_trauma", 0.06, global_position)
	queue_free()


func _draw() -> void:
	# a dark iron ball with glowing slits that pulse while it pours
	var pulse := 0.7 + 0.3 * sin(_t * 6.0)
	draw_circle(Vector2.ZERO, 11.0, shell_color)
	draw_circle(Vector2(-3, -3), 4.0, shell_color.lightened(0.25))
	for i in 3:
		var a := -PI * 0.5 + (i - 1) * 0.7
		var d := Vector2.from_angle(a)
		draw_line(d * 4.0, d * 9.5, Color(ember_color, pulse), 2.5)
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, shell_color.darkened(0.5), 1.5)
