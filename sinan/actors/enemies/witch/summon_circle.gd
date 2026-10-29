extends Node2D
## Rune circle drawn flat on the ground while the witch channels a summon.
## Set `progress` (0..1) from the owner; it fills the outer ring. Replace this
## node with a sprite/animation later if you like - the witch only sets
## `visible` and `progress`.

@export var radius := 40.0
## Vertical squash so the circle reads as lying on the floor.
@export var flatten := 0.32
@export var color := Color(0.75, 0.3, 1.0)
@export var rune_color := Color(1.0, 0.4, 0.9)
@export var progress_color := Color(1.0, 0.9, 1.0, 0.9)

var progress := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	View.redraw(self)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, flatten))
	var a := 0.35 + 0.65 * progress
	draw_circle(Vector2.ZERO, radius * 1.1, Color(color, 0.08 * a))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.8 * a), 3.0, true)
	draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 40, Color(color, 0.6 * a), 2.0, true)
	# rune ticks spinning one way, star the other
	for i in 12:
		var d := Vector2.from_angle(_t * 1.5 + i * TAU / 12.0)
		draw_line(d * radius * 0.8, d * radius * 0.97, Color(rune_color, a), 2.0)
	var star := PackedVector2Array()
	for i in 6:
		star.append(Vector2.from_angle(-_t * 0.8 + i * 2.0 * TAU / 5.0) * radius * 0.75)
	draw_polyline(star, Color(color, 0.7 * a), 1.5, true)
	# progress ring: how close the summon is to finishing
	draw_arc(Vector2.ZERO, radius * 1.2, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, progress_color, 4.0, true)
