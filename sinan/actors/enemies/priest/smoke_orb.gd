extends Node2D
## The Censer Priest's smoke orb: a smouldering ball lobbed in a readable arc.
## Where it lands - on a board, the floor, or its target point in the air - it
## becomes a SmokeVent that slowly fills the area with rising smoke.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const SmokeVent := preload("res://sinan/actors/enemies/priest/smoke_vent.gd")

var target := Vector2.ZERO
var shooter  # the priest that threw it (the death camera looks at it)
var flight_time := 0.9
var gravity := 900.0
## Called with the SmokeVent once it lands.
var on_vent: Callable
## The vent stays in the air where the orb stopped (painting sequences).
var floating := false
var hit_damage := 0.5
var color := Color(0.25, 0.2, 0.26)
var glow_color := Color(1.0, 0.55, 0.25)

var _vel := Vector2.ZERO
var _t := 0.0
var _trail: CPUParticles2D
var _player: Node2D


## Call after setting position / target, before add_child.
func aim() -> void:
	var d := target - position
	_vel = Vector2(d.x / flight_time, (d.y - 0.5 * gravity * flight_time * flight_time) / flight_time)


func _ready() -> void:
	z_index = 4
	_player = get_tree().get_first_node_in_group("player")
	_trail = FxLib.emitter({
		"one_shot": false, "amount": 24, "life": 0.6, "v_min": 5.0, "v_max": 25.0,
		"gravity": Vector2(0, -40), "ramp": FxLib.smoke_ramp(0.5), "s_min": 0.15, "s_max": 0.3,
		"curve": FxLib.grow(),
	})
	_trail.local_coords = false
	add_child(_trail)


func _physics_process(delta: float) -> void:
	_t += delta
	_vel.y += gravity * delta
	var next := global_position + _vel * delta
	# bursts on boards and the floor (rays do hit one-way boards)
	var hit := get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(global_position, next, 1, _exclude()))
	if not hit.is_empty():
		global_position = hit.position + Vector2(0, -10)
		_burst()
		return
	global_position = next
	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) < 22.0:
		if _player.has_method("take_damage"):
			_player.take_damage(hit_damage, global_position, 160.0, false, shooter)
		_burst()
		return
	if _t >= flight_time:
		_burst()
	queue_redraw()


func _exclude() -> Array[RID]:
	var ex: Array[RID] = []
	if _player is CollisionObject2D:
		ex.append((_player as CollisionObject2D).get_rid())
	return ex


func _burst() -> void:
	set_physics_process(false)
	var vent := SmokeVent.new()
	vent.floating = floating
	vent.position = get_parent().to_local(global_position) if get_parent() is Node2D else global_position
	get_parent().add_child(vent)
	if on_vent.is_valid():
		on_vent.call(vent)
	FxLib.smoke_burst(get_parent(), global_position, 0.6, color, 10)
	FxLib.flash_light(get_parent(), global_position, glow_color, 1.2, 1.0, 0.2)
	_trail.emitting = false
	_trail.reparent(get_parent())
	get_tree().create_timer(1.0).timeout.connect(_trail.queue_free)
	queue_free()


func _draw() -> void:
	var pulse := 0.8 + 0.2 * sin(_t * 18.0)
	draw_circle(Vector2.ZERO, 8.0, color)
	draw_circle(Vector2.ZERO, 5.0 * pulse, glow_color)
	draw_circle(Vector2(-2, -2), 2.0, Color(1, 0.9, 0.7))
