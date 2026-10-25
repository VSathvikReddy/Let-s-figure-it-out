extends Node2D
## Aim preview. Three modes:
##  ROCKET   dotted arc (simulates the missile, or a plain lob for the orb)
##           + a ring where it lands
##  PISTOL   dashed straight line to the hit
##  PAINTING dotted arc into the painting, dots shrinking with depth

const Missile := preload("res://sinan/fx/missile.gd")
const DepthFlight := preload("res://sinan/fx/depth_flight.gd")

enum Mode { ROCKET, PISTOL, PAINTING }

const STRAIGHT_RANGE := 1400.0

var _mode := Mode.ROCKET
var _pts := PackedVector2Array()
var _sizes := PackedFloat32Array()
var _hit := false
var _ready_shot := true
var _end_radius := 0.0
var _ring_radius := 0.0                 # ring drawn where an arc/lob lands
var _tint := Color(1.0, 0.92, 0.65)    # dot colour for arc/lob previews


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3


## Call from a physics step. arc = rocket (simulates the missile integrator);
## otherwise a straight pistol line.
func update_path(from: Vector2, dir: Vector2, shooter: RID, ready_shot: bool, arc := true) -> void:
	_ready_shot = ready_shot
	_mode = Mode.ROCKET if arc else Mode.PISTOL
	_pts.clear()
	_hit = false
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = [shooter]
	if not arc:
		var end := from + dir * STRAIGHT_RANGE
		var sh := space.intersect_ray(PhysicsRayQueryParameters2D.create(from, end, 1, ex))
		_hit = not sh.is_empty()
		_pts.append(from)
		_pts.append(sh.position if _hit else end)
		queue_redraw()
		return
	_ring_radius = Missile.BLAST_RADIUS
	_tint = Color(1.0, 0.92, 0.65)
	var pos := from
	var v := dir * Missile.START_SPEED
	var dt := 0.03
	for i in 28:
		v += Vector2(0.0, Missile.GRAVITY) * dt
		v += v.normalized() * Missile.ACCEL * dt
		v = v.limit_length(Missile.MAX_SPEED)
		var nxt := pos + v * dt
		var h := space.intersect_ray(PhysicsRayQueryParameters2D.create(pos, nxt, 1, ex))
		if not h.is_empty():
			_pts.append(h.position)
			_hit = true
			break
		_pts.append(nxt)
		pos = nxt
	queue_redraw()


## Plain ballistic lob (orb): velocity + gravity, stops at the first hit.
func update_lob(from: Vector2, vel: Vector2, gravity: float, shooter: RID, ready_shot: bool, ring: float, tint: Color) -> void:
	_ready_shot = ready_shot
	_mode = Mode.ROCKET
	_ring_radius = ring
	_tint = tint
	_pts.clear()
	_hit = false
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = [shooter]
	var pos := from
	var v := vel
	var dt := 0.03
	for i in 40:
		v.y += gravity * dt
		var nxt := pos + v * dt
		var h := space.intersect_ray(PhysicsRayQueryParameters2D.create(pos, nxt, 1, ex))
		if not h.is_empty():
			_pts.append(h.position)
			_hit = true
			break
		_pts.append(nxt)
		pos = nxt
	queue_redraw()


## Preview a shot into the painting. end_radius = blast ring at the target (0 = none).
func update_paint(from: Vector2, to: Vector2, end_scale: float, arc_height: float, ready_shot: bool, end_radius: float) -> void:
	_ready_shot = ready_shot
	_mode = Mode.PAINTING
	_end_radius = end_radius
	_pts.clear()
	_sizes.clear()
	var steps := 16
	for i in range(1, steps + 1):
		var k := float(i) / steps
		_pts.append(DepthFlight.point_at(from, to, arc_height, k))
		_sizes.append(DepthFlight.scale_at(end_scale, k))
	queue_redraw()


func _draw() -> void:
	var n := _pts.size()
	var base := 0.55 if _ready_shot else 0.2
	match _mode:
		Mode.PISTOL:
			if n == 2:
				draw_dashed_line(_pts[0], _pts[1], Color(1.0, 0.4, 0.3, base * 0.5), 1.5, 8.0)
				if _hit:
					draw_circle(_pts[1], 3.0, Color(1.0, 0.4, 0.3, base))
		Mode.PAINTING:
			for i in n:
				draw_circle(_pts[i], 3.0 * _sizes[i], Color(1.0, 0.85, 0.35, base))
			if _end_radius > 0.0 and n > 0:
				draw_arc(_pts[n - 1], _end_radius, 0.0, TAU, 40, Color(1.0, 0.75, 0.3, base * 0.6), 1.5, true)
		Mode.ROCKET:
			for i in n:
				var f := 1.0 - float(i) / float(maxi(n, 1))
				draw_circle(_pts[i], lerpf(1.0, 2.6, f), Color(_tint, base * lerpf(0.15, 1.0, f)))
			if _hit and n > 0:
				var p := _pts[n - 1]
				draw_arc(p, _ring_radius, 0.0, TAU, 48, Color(_tint.lerp(Color(1.0, 0.55, 0.25), 0.5), base * 0.6), 2.0, true)
				draw_circle(p, 3.0, Color(_tint, base))
