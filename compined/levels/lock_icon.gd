extends Control
## A padlock drawn over a locked painting card. play_unlock() opens it: the
## shackle pops up, the lock jumps, glows gold, then fades away.

const BODY_COLOR := Color(0.85, 0.68, 0.3)
const DARK_COLOR := Color(0.25, 0.18, 0.08)

## 0 = closed, 1 = shackle fully popped open.
var open_amount := 0.0:
	set(value):
		open_amount = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var center := size / 2.0
	var body := Rect2(center + Vector2(-26, -6), Vector2(52, 40))
	# the shackle (the bent bar on top) lifts and tilts as it opens
	var lift := 16.0 * open_amount
	var shackle_center := center + Vector2(0, -8 - lift)
	draw_arc(shackle_center, 16.0, PI, TAU, 24, DARK_COLOR, 9.0, true)
	draw_arc(shackle_center, 16.0, PI, TAU, 24, BODY_COLOR, 6.0, true)
	draw_line(shackle_center + Vector2(-16, 0), shackle_center + Vector2(-16, 6 + lift), BODY_COLOR, 6.0)
	if open_amount < 0.5:   # the right leg slides out of the body when it opens
		draw_line(shackle_center + Vector2(16, 0), shackle_center + Vector2(16, 6 + lift), BODY_COLOR, 6.0)
	# the body with a keyhole
	draw_rect(body.grow(3), DARK_COLOR)
	draw_rect(body, BODY_COLOR)
	draw_circle(center + Vector2(0, 8), 5.0, DARK_COLOR)
	draw_rect(Rect2(center + Vector2(-2, 10), Vector2(4, 12)), DARK_COLOR)


## Opens the lock, then fades it out. Await it to know when it is done.
func play_unlock() -> void:
	pivot_offset = size / 2.0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.25, 0.15)          # it jumps...
	tween.tween_property(self, "open_amount", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate", Color(1.6, 1.4, 0.8), 0.25)   # ...glows gold...
	tween.tween_interval(0.35)
	tween.tween_property(self, "scale", Vector2.ONE * 1.8, 0.4)            # ...and fades away
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.4)
	await tween.finished
