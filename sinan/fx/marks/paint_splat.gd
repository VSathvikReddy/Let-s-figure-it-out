extends Node2D
## A big paint splat that pops onto a surface, sits for a moment, then fades.
## Irregular blob with spikes, a darker rim, a wet highlight and flung droplets.

var radius := 60.0
var color := Color(0.2, 0.42, 0.9)
var shade := Color(0.07, 0.15, 0.42)
var life := 2.5
## Surface normal to lie flat against (studio floor/wall). ZERO = flat on the canvas.
var flat_normal := Vector2.ZERO

var _outer := PackedVector2Array()
var _inner := PackedVector2Array()
var _drops: Array[Vector3] = []  # x, y, r
var _t := 0.0


func _ready() -> void:
	z_index = 0 if get_parent() is Parallax2D else 1
	var n := 26
	for i in n:
		var a := float(i) / n * TAU
		var r := radius * randf_range(0.7, 1.05) * (1.6 if i % 4 == 0 else 1.0)
		_outer.append(Vector2.from_angle(a) * r)
	for i in 12:
		var a := randf() * TAU
		var d := radius * randf_range(1.25, 2.2)
		_drops.append(Vector3(cos(a) * d, sin(a) * d, radius * randf_range(0.05, 0.16)))
	if flat_normal != Vector2.ZERO:
		var rot := flat_normal.angle() + PI / 2.0
		for i in _outer.size():
			_outer[i] = Vector2(_outer[i].x, _outer[i].y * 0.35).rotated(rot)
		for i in _drops.size():
			var p := Vector2(_drops[i].x, _drops[i].y * 0.35).rotated(rot)
			_drops[i] = Vector3(p.x, p.y, _drops[i].z)
	for p in _outer:
		_inner.append(p * 0.78)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > life:
		queue_free()


func _draw() -> void:
	# pop in with a little overshoot, then fade over the last 40%
	var k := _t / 0.15
	var s := (1.0 - pow(1.0 - minf(k, 1.0), 3.0)) * 1.12 if k < 1.0 else lerpf(1.12, 1.0, minf((k - 1.0) * 2.0, 1.0))
	var a := 1.0 - smoothstep(life * 0.6, life, _t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	draw_colored_polygon(_outer, Color(shade, a))
	draw_colored_polygon(_inner, Color(color, a))
	for d in _drops:
		draw_circle(Vector2(d.x, d.y), d.z, Color(color, a))
	draw_circle(_inner[3] * 0.4, radius * 0.18, Color(1, 1, 1, 0.35 * a))
