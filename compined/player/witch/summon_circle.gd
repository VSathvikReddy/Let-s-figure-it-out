extends Node2D
## The rune circle shown under the witch while she summons ghosts.
## The player script sets `visible` and `progress` (0..1, fills the outer ring).
## Its Light child glows brighter as the summon fills up.

@export var radius := 60.0
## Vertical squash, so the circle looks like it lies flat.
@export var flatten := 0.32
@export var color := Color(1.0, 0.36, 0.42)
@export var rune_color := Color(1.0, 0.7, 0.55)
@export var progress_color := Color(1.0, 0.9, 1.0, 0.9)

## How bright the Light child gets when the circle is full.
@export var max_light := 0.8

var progress := 0.0
var _time := 0.0

@onready var light: PointLight2D = get_node_or_null("Light")


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if light:
		light.energy = lerpf(0.4, max_light, progress) * (1.0 + 0.1 * sin(_time * 12.0))
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, flatten))
	var strength := 0.45 + 0.4 * progress   # brighter as the summon fills up
	draw_circle(Vector2.ZERO, radius * 1.1, Color(color, 0.07 * strength))      # faint glow under it
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(color, strength), 2.5, true)
	draw_arc(Vector2.ZERO, radius * 0.78, 0.0, TAU, 48, Color(color, 0.7 * strength), 1.5, true)

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
	draw_arc(Vector2.ZERO, radius * 1.2, -PI / 2.0, -PI / 2.0 + TAU * progress, 64, Color(progress_color, 0.7), 3.0, true)
