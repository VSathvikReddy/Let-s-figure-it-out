@tool
class_name HangingBoard
extends Node2D
## A wooden board hung from the ceiling by two chains - it swings like a swing.
## Everything is a node in hanging_board.tscn, so move / resize it all in the
## editor:
##   LeftAnchor, RightAnchor - Marker2D: where the chains hang from (ceiling)
##   LeftChain, RightChain   - ChainRope: Start Node = an anchor, End Node = a bracket
##   Board                   - AnimatableBody2D the player stands on (one-way)
##     Sprite2D, CollisionShape2D - the plank art and its walkable top
##     LeftBracket, RightBracket  - Marker2D: where the chains attach
##     NavLeft, NavRight          - Marker2D: walkable ends for enemy navigation
##     LandingArea                - Area2D: who is on it (reaches above the board,
##                                  so it sees a body falling in before it lands)
##
## Physics: the board is a rigid body hanging from two chains that behave like
## stiff springs under TENSION (they pull, never push). Gravity sags it into its
## chains; landing on it dips it and it bounces back up on the chains; standing
## on one end stretches that chain more, so the board tilts toward you; a push
## swings it out like a swing seat. Landings, jumping off, running on it and
## rocket blasts all push it. Tune the feel in the Inspector (Swing, Chains,
## Pushes). The board rests exactly where you placed it in the editor.

@export_group("Swing")
## Board weight compared to the player (1). Heavier = harder to push.
@export var mass := 4.0
@export var gravity := 980.0
## Swing speed lost per second (0 = swings forever, 1 = settles in ~3 swings).
@export_range(0.0, 3.0) var swing_damping := 0.15
## Rotation speed lost per second.
@export_range(0.0, 10.0) var spin_damping := 0.8
## Fastest it may swing (px/s) - keeps wild hits under control.
@export var max_speed := 650.0
## Fastest it may turn (radians/second) - stops an off-centre landing flipping it.
@export var max_spin := 4.0

@export_group("Chains")
## How hard each chain pulls back per pixel it is stretched. Lower = bouncier,
## deeper dips; higher = tighter chains.
@export var chain_stiffness := 300.0
## How quickly a bounce on the chains dies out.
@export var chain_damping := 6.0
## Physics sub-steps per frame (more = steadier with stiff chains).
@export_range(1, 8) var substeps := 4

@export_group("Pushes")
## How much of a landing body's momentum goes into the board.
@export var landing_impulse := 0.8
## Push when someone jumps off it.
@export var jump_off_impulse := 0.6
## Walking: speeding up / stopping on the board pushes it the other way.
@export var walk_push := 0.8
## Standing weight (x body weight) - sags the board and tilts it toward
## whoever stands on an end.
@export var standing_weight := 1.5
## Faint breeze (px/s^2) so boards never look frozen.
@export var idle_sway := 6.0
## Rocket blasts within this distance shove the board.
@export var blast_reach := 260.0
@export var blast_push := 260.0

var _board: AnimatableBody2D
var _anchors: Array[Node2D] = []
var _brackets: Array[Node2D] = []
var _nav: Array[Node2D] = []
var _area: Area2D

var _rope_len: Array[float] = []
var _inertia := 1.0
var _vel := Vector2.ZERO
var _w := 0.0
var _last_vy := {}   # body -> vertical speed last frame (to catch landings)
var _last_vx := {}   # body -> horizontal speed last frame (walk push)
var _age := 0.0
var _seed := 0.0


func _ready() -> void:
	add_to_group("platforms")
	_seed = randf() * TAU
	_board = get_node_or_null("Board") as AnimatableBody2D
	_anchors = [get_node_or_null("LeftAnchor") as Node2D, get_node_or_null("RightAnchor") as Node2D]
	if _board:
		_board.add_to_group("one_way_platforms")
		# the script moves it every physics frame; sync would reset it to the server state
		_board.sync_to_physics = false
		_brackets = [_board.get_node_or_null("LeftBracket") as Node2D, _board.get_node_or_null("RightBracket") as Node2D]
		_nav = [_board.get_node_or_null("NavLeft") as Node2D, _board.get_node_or_null("NavRight") as Node2D]
		_area = _board.get_node_or_null("LandingArea") as Area2D
	if not Engine.is_editor_hint() and _valid():
		_measure()


func _valid() -> bool:
	return _board != null and not (null in _anchors) and _brackets.size() == 2 and not (null in _brackets)


## Chain rest lengths and rotational inertia from the layout as placed in the
## editor. Each chain's rest length is a little shorter than placed, by exactly
## the stretch the board's weight causes - so it hangs where you put it.
func _measure() -> void:
	_rope_len.clear()
	for i in 2:
		var d := _board.transform * _brackets[i].position - _anchors[i].position
		var up := maxf(d.normalized().y, 0.3)   # steep chains carry the weight directly
		var stretch := mass * gravity * 0.5 / up / maxf(chain_stiffness, 1.0)
		_rope_len.append(maxf(d.length() - stretch, 1.0))
	# a thick plank with iron brackets: a bit more rotational inertia than a thin rod
	var span := _brackets[0].position.distance_to(_brackets[1].position) * 1.4
	_inertia = mass * span * span / 12.0


## The walking surface (world points, live) for enemy navigation.
func nav_surface() -> Dictionary:
	if _nav.size() < 2 or null in _nav:
		return {"left": global_position + Vector2(-80, 0), "right": global_position + Vector2(80, 0), "body": _board, "one_way": true}
	return {"left": _nav[0].global_position, "right": _nav[1].global_position, "body": _board, "one_way": true,
		"left_node": _nav[0], "right_node": _nav[1]}


## Push the board at a world point with an impulse (mass 1 x velocity).
func push(world_point: Vector2, impulse: Vector2) -> void:
	if _board == null:
		return
	var r := to_local(world_point) - _board.position
	_vel += impulse / mass
	_w = clampf(_w + r.cross(impulse) / _inertia, -max_spin, max_spin)


## Called through the "platforms" group by rocket explosions.
func on_blast(pos: Vector2, _radius: float) -> void:
	if _board == null:
		return
	var d := _board.global_position.distance_to(pos)
	if d > blast_reach:
		return
	var away := (_board.global_position - pos).normalized()
	push(pos, away * blast_push * mass * (1.0 - d / blast_reach))


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _valid() or _rope_len.is_empty():
		return
	_age += delta
	_read_riders(delta)
	var pos := _board.position
	var rot := _board.rotation
	var h := delta / substeps
	for _s in substeps:
		# gravity + a faint breeze
		var force := Vector2(sin(_age * 0.7 + _seed) * idle_sway * mass, gravity * mass)
		var torque := 0.0
		# chains: springs that only pull (tension), with damping along the chain
		for i in 2:
			var arm := _brackets[i].position.rotated(rot)
			var d := pos + arm - _anchors[i].position
			var l := d.length()
			if l <= _rope_len[i] or l < 0.001:
				continue  # slack: the chain does nothing
			var n := d / l
			var point_vel := _vel + Vector2(-_w * arm.y, _w * arm.x)
			var tension := maxf(chain_stiffness * (l - _rope_len[i]) + chain_damping * point_vel.dot(n), 0.0)
			var f := -n * tension
			force += f
			torque += arm.cross(f)
		_vel += force / mass * h
		_w += torque / _inertia * h
		_vel *= exp(-swing_damping * h)
		_w *= exp(-spin_damping * h)
		_vel = _vel.limit_length(max_speed)
		_w = clampf(_w, -max_spin, max_spin)
		pos += _vel * h
		rot += _w * h
	_board.position = pos
	_board.rotation = rot


## Bodies on the board: landings, jump-offs, walking and standing weight.
func _read_riders(delta: float) -> void:
	if _area == null:
		return
	var seen := {}
	for b in _area.get_overlapping_bodies():
		if not (b is CharacterBody2D):
			continue
		var cb := b as CharacterBody2D
		seen[b] = true
		var bm: float = b.get_meta("mass", 1.0)
		if bm <= 0.0:
			continue
		var vy := cb.velocity.y
		var vx := cb.velocity.x
		var last: float = _last_vy.get(b, 0.0)
		var at := cb.global_position
		if last > 150.0 and vy < 60.0:
			# landed: its momentum goes into the board (down and sideways)
			push(at, Vector2(vx * 0.6, last) * bm * landing_impulse)
		elif last > -60.0 and vy < -300.0:
			# jumped off: kicks the board down and back
			push(at, Vector2(-vx, -vy * 0.5) * bm * jump_off_impulse)
		elif absf(vy) < 120.0:
			if _last_vx.has(b):
				# walking: speeding up shoves the board back, stopping drags it along
				push(at, Vector2(-(vx - float(_last_vx[b])), 0.0) * bm * walk_push)
			# standing weight (tilts it toward whoever stands on an end)
			push(at, Vector2(0.0, gravity * delta) * bm * standing_weight)
		_last_vy[b] = vy
		_last_vx[b] = vx
	for b in _last_vy.keys():
		if not seen.has(b):
			_last_vy.erase(b)
			_last_vx.erase(b)
