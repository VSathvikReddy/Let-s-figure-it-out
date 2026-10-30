extends Control
## The countdown next to the hearts while the player heals inside the veil:
## a ring that fills up around a small heart, and the seconds left until the
## next heart comes back ("+1 in 7s"). Hidden when she is not healing.

@export var ring_color := Color(0.75, 0.55, 1.0)       ## veil violet
@export var ring_background := Color(0.1, 0.07, 0.14, 0.7)

const HEART := preload("res://compined/ui/hearts/heart_00.png")

## 0..1 how full the ring is, and the seconds left (set by the health HUD).
var progress := 0.0
var seconds_left := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var radius := size.y * 0.42
	var center := Vector2(radius + 2.0, size.y / 2.0)
	# ring: dark background, then the part that has filled up
	draw_circle(center, radius, ring_background)
	draw_arc(center, radius - 3.0, 0.0, TAU, 40, Color(ring_color, 0.25), 4.0, true)
	draw_arc(center, radius - 3.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 40, ring_color, 4.0, true)
	# a small heart in the middle that brightens as the ring fills
	var heart_size := Vector2.ONE * radius * 1.25
	draw_texture_rect(HEART, Rect2(center - heart_size / 2.0, heart_size), false, Color(1, 1, 1, 0.45 + 0.55 * progress))
	# "+1 in 7s" next to the ring
	var font := get_theme_default_font()
	var text := "+1 in %ds" % ceili(seconds_left)
	var at := Vector2(center.x + radius + 8.0, center.y + 6.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0.08, 0.04, 0.1))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.85, 1.0))
