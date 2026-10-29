@tool
class_name EntropyIcon
extends Control
## The Entropy symbol: a violet diamond with a swirl in it. Entropy is earned
## by restoring the painting and pays for about half of the skill tree.

const COLOR := Color(0.72, 0.5, 1.0)


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(16, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw(self, size * 0.5, minf(size.x, size.y) * 0.5)


## Draw the symbol on any CanvasItem (the skill tree board uses it too).
static func draw(ci: CanvasItem, at: Vector2, r: float, color := COLOR) -> void:
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.8, 0), at + Vector2(0, r), at + Vector2(-r * 0.8, 0)]), color)
	ci.draw_arc(at, r * 0.42, 0.3, TAU * 0.8, 10, Color(0.12, 0.05, 0.2), maxf(1.0, r * 0.18), true)
