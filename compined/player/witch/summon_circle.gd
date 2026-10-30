extends Node2D
## The rune circle shown under the witch while she summons ghosts.
## The player script sets `visible` and `progress` (0..1, fills the outer ring).

@export var radius := 40.0
## Vertical squash, so the circle looks like it lies flat.
@export var flatten := 0.32
@export var color := Color(1.0, 0.36, 0.42)
@export var rune_color := Color(1.0, 0.7, 0.55)
@export var progress_color := Color(1.0, 0.9, 1.0, 0.9)

var progress := 0.0
var _time := 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, flatten))
	var strength := 0.35 + 0.65 * progress   # brighter as the summon fills up
	draw_circle(Vector2.ZERO, radius * 1.1, Color(color, 0.08 * strength))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.8 * strength), 3.0, true)
	draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 40, Color(color, 0.6 * strength), 2.0, true)

	# rune ticks spin one way...
	for i in 12:
		var direction := Vector2.from_angle(_time * 1.5 + i * TAU / 12.0)
		draw_line(direction * radius * 0.8, direction * radius * 0.97, Color(rune_color, strength), 2.0)
	# ...and the star the other way
	var star := PackedVector2Array()
	for i in 6:
		star.append(Vector2.from_angle(-_time * 0.8 + i * 2.0 * TAU / 5.0) * radius * 0.75)
	draw_polyline(star, Color(color, 0.7 * strength), 1.5, true)

	# outer ring: how close the summon is to finishing
	draw_arc(Vector2.ZERO, radius * 1.2, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, progress_color, 4.0, true)
