extends Node2D
## Pulsing "something is coming here" marker: a faint filled disc, a slowly
## spinning dashed ring that tightens over time, and a centre dot. Lives inside
## a painting layer so it scrolls with the parallax. Whoever creates it frees it.

var radius := 40.0
var color := Color(1.0, 0.25, 0.45)
var _t := 0.0


func _ready() -> void:
	z_index = 0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var appear := clampf(_t / 0.4, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var r := radius * (1.0 - 0.15 * pulse) * appear
	draw_circle(Vector2.ZERO, r, Color(color, 0.06 + 0.05 * pulse))
	var dashes := 10
	for i in dashes:
		var a0 := _t * 1.2 + i * TAU / dashes
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU / dashes * 0.55, 6, Color(color, 0.55 * appear), 1.5, true)
	draw_circle(Vector2.ZERO, 2.0 + pulse, Color(color, 0.7 * appear))
