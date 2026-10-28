extends Node2D
## A single curved brush stroke (the brush staff's swing swoosh). It paints
## itself along an arc in front of the node, tapered at both ends, then fades.
## Rotate the node to aim it.

var radius := 45.0
var sweep := 2.0      # radians covered by the arc
var width := 12.0
var color := Color(0.2, 0.42, 0.9)
var shade := Color(0.07, 0.15, 0.42)
var life := 0.35
var draw_time := 0.08  # how long the stroke takes to paint itself
var _t := 0.0


func _ready() -> void:
	z_index = 3


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > life:
		queue_free()


func _draw() -> void:
	var reveal := clampf(_t / draw_time, 0.0, 1.0)
	var a := 1.0 - clampf((_t - draw_time) / (life - draw_time), 0.0, 1.0)
	var steps := 20
	var a0 := -sweep * 0.5
	# Two passes of round-jointed segments: darker rim, then the paint body.
	for pass_i in 2:
		var col := Color(shade, a) if pass_i == 0 else Color(color, a)
		var grow := 3.0 if pass_i == 0 else 0.0
		for i in steps:
			var u0 := float(i) / steps
			var u1 := float(i + 1) / steps
			var um := (u0 + u1) * 0.5
			var w := width * sin(PI * um) * (0.6 + 0.4 * um) + grow  # tapered, heavier toward the end
			if w < 0.5:
				continue
			var p0 := Vector2.from_angle(a0 + sweep * reveal * u0) * radius
			var p1 := Vector2.from_angle(a0 + sweep * reveal * u1) * radius
			draw_line(p0, p1, col, w, true)
			draw_circle(p1, w * 0.5, col)
	# dry-brush highlight streak
	var hl := PackedVector2Array()
	for i in steps + 1:
		var u := float(i) / steps
		hl.append(Vector2.from_angle(a0 + sweep * reveal * u) * (radius - width * 0.15))
	draw_polyline(hl, Color(1, 1, 1, 0.35 * a), 1.5, true)
