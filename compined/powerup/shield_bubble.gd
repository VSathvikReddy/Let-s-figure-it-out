extends Node2D
## The bubble around the player while the Shield power-up is on. It shimmers,
## flashes when it blocks a hit, and blinks in its last second.

@export var radius := 58.0
@export var color := Color(0.45, 0.7, 1.0)

## Seconds of shield left (set by the player); hidden at 0.
var time_left := 0.0
var _time := 0.0
var _flash := 0.0


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 4.0, 0.0)
	visible = time_left > 0.0 and (time_left > 1.0 or int(_time * 10.0) % 2 == 0)
	queue_redraw()


## Called when it blocks a hit.
func flash() -> void:
	_flash = 1.0


func _draw() -> void:
	var shimmer := 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, radius, Color(color, 0.12 + 0.25 * _flash))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color.lightened(0.3), 0.6 + 0.4 * _flash), 2.5 + 3.0 * _flash, true)
	# a moving shine on the bubble
	var shine_at := _time * 1.5
	draw_arc(Vector2.ZERO, radius * 0.85, shine_at, shine_at + 0.7, 12, Color(1, 1, 1, 0.35 + 0.3 * shimmer), 3.0, true)
