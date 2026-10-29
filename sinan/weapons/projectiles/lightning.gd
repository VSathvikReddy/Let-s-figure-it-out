extends Node2D
## A crackling electric bolt along a list of world points (the wand's shot and
## each chain jump). Jagged, re-jitters a few times, then fades - about 0.15 s.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")

var points := PackedVector2Array()   # world points, set before add_child
var color := Color(0.65, 0.85, 1.0)
var width := 3.0
var life := 0.15

var _t := 0.0
var _jagged := PackedVector2Array()
var _rejag := 0.0


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 4
	material = FxLib.additive()
	_jag()


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	_rejag -= delta
	if _rejag <= 0.0:
		_rejag = 0.04
		_jag()
	queue_redraw()


## Break each straight segment into short pieces pushed sideways at random.
func _jag() -> void:
	_jagged.clear()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(2, int(a.distance_to(b) / 22.0))
		var side := (b - a).orthogonal().normalized()
		for k in n:
			var f := float(k) / n
			var off := 0.0 if k == 0 else randf_range(-9.0, 9.0) * sin(f * PI)
			_jagged.append(a.lerp(b, f) + side * off)
	if not points.is_empty():
		_jagged.append(points[-1])


func _draw() -> void:
	if _jagged.size() < 2:
		return
	var fade := 1.0 - _t / life
	draw_polyline(_jagged, Color(color, 0.35 * fade), width * 3.5, true)
	draw_polyline(_jagged, Color(color, fade), width, true)
	draw_polyline(_jagged, Color(1, 1, 1, fade), width * 0.4, true)
