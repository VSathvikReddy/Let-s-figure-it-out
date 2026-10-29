extends Node2D
## Pulsing "something is coming here" marker: a faint filled disc, a slowly
## spinning dashed ring that tightens over time, and a centre dot. Lives inside
## a painting layer so it scrolls with the parallax. Whoever creates it frees it.
## Drawn ONCE; the spin, pulse and fade-in are the node's rotation, scale and
## modulate (no redraw every frame).

var radius := 40.0
var color := Color(1.0, 0.25, 0.45)
var _t := 0.0


func _ready() -> void:
	z_index = 0
	scale = Vector2.ONE * 0.01
	modulate.a = 0.0


func _process(delta: float) -> void:
	_t += delta
	var appear := clampf(_t / 0.4, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	rotation = _t * 1.2
	scale = Vector2.ONE * maxf((1.0 - 0.15 * pulse) * appear, 0.01)
	modulate.a = appear


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(color, 0.08))
	var dashes := 10
	for i in dashes:
		var a0 := i * TAU / dashes
		draw_arc(Vector2.ZERO, radius, a0, a0 + TAU / dashes * 0.55, 6, Color(color, 0.55), 1.5, true)
	draw_circle(Vector2.ZERO, 2.5, Color(color, 0.7))
