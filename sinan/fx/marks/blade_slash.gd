extends Node2D
## A sharp crescent blade slash: sweeps open fast along an arc, thick at the
## leading edge and tapering to a thin tail, with a white-hot cutting edge, a
## soft glow behind it and a few speed lines. Fades quickly.
## Angles are in the node's local space (0 = +x); rotate / mirror the node to aim.

var radius := 30.0
var thickness := 12.0
var start_angle := deg_to_rad(-110.0)
var end_angle := deg_to_rad(55.0)
var color := Color(1.0, 0.92, 0.85)
var glow_color := Color(1.0, 0.35, 0.25)
var edge_color := Color(1.0, 1.0, 1.0)
var sweep_time := 0.06   # how long the arc takes to open
var life := 0.22
var speed_lines := 3

var _t := 0.0


func _ready() -> void:
	z_index = 4


func _process(delta: float) -> void:
	_t += delta
	View.redraw(self)
	if _t >= life:
		queue_free()


func _draw() -> void:
	var reveal := 1.0 - pow(1.0 - clampf(_t / sweep_time, 0.0, 1.0), 2.0)
	var fade := 1.0 - clampf((_t - sweep_time) / maxf(life - sweep_time, 0.01), 0.0, 1.0)
	if fade <= 0.0:
		return
	var steps := 18
	var head := lerpf(start_angle, end_angle, reveal)
	# the tail catches up as it fades, so the crescent shrinks toward the tip
	var tail := lerpf(start_angle, head, 1.0 - fade)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var u := float(i) / steps          # 0 tail .. 1 head
		var a := lerpf(tail, head, u)
		var w := thickness * pow(u, 1.4) * fade + 0.4
		var d := Vector2.from_angle(a)
		outer.append(d * radius)
		inner.append(d * (radius - w))
	# glow (slightly bigger), body, then the bright cutting edge
	# raw quads (draw_primitive): no triangulation, so paper-thin tails are fine
	var gc := Color(glow_color, 0.35 * fade)
	var bc := Color(color, 0.95 * fade)
	for i in steps:
		draw_primitive(PackedVector2Array([outer[i] * 1.08, outer[i + 1] * 1.08, inner[i + 1] * 0.94, inner[i] * 0.94]),
			PackedColorArray([gc, gc, gc, gc]), PackedVector2Array())
	for i in steps:
		draw_primitive(PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]]),
			PackedColorArray([bc, bc, bc, bc]), PackedVector2Array())
	draw_polyline(outer, Color(edge_color, fade), 2.0, true)
	# speed lines trailing the head
	for k in speed_lines:
		var a := head - (0.25 + 0.18 * k) * signf(end_angle - start_angle)
		var r := radius * (1.12 + 0.08 * k)
		var d := Vector2.from_angle(a)
		draw_line(d * r, d * (r - thickness * 0.8), Color(color, 0.6 * fade), 1.5, true)
