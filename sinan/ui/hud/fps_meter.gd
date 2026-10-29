extends Control
## FPS meter (top right, under the run timer): the frame rate, the average frame
## time, and a bar for each of the last frames - green fits 60 fps (16.7 ms),
## yellow is 30-60 fps, red is slower. F2 hides / shows it.
## Added by the HUD; works paused too (skill tree, menus).

const BARS := 90
const GRAPH_H := 28.0
const BUDGET_MS := 1000.0 / 60.0

var _times := PackedFloat32Array()
var _last := 0
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -BARS * 2.0 - 24.0
	offset_right = -16.0
	offset_top = 52.0
	offset_bottom = 52.0 + GRAPH_H + 20.0
	_font = ThemeDB.fallback_font
	_times.resize(BARS)
	_last = Time.get_ticks_usec()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		visible = not visible


func _process(_delta: float) -> void:
	# real time between frames (not delta: that is slowed by hit-stop / pauses)
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0
	_last = now
	_times.remove_at(0)
	_times.append(ms)
	if visible:
		queue_redraw()


func _draw() -> void:
	var avg := 0.0
	var worst := 0.0
	for t in _times:
		avg += t
		worst = maxf(worst, t)
	avg /= BARS
	var w := size.x
	draw_rect(Rect2(0, 0, w, size.y), Color(0, 0, 0, 0.45))
	var col := Color(0.5, 1.0, 0.5) if avg <= BUDGET_MS * 1.1 else (Color(1.0, 0.85, 0.35) if avg <= BUDGET_MS * 2.0 else Color(1.0, 0.4, 0.35))
	draw_string(_font, Vector2(6, 14), "%d FPS  %.1f ms  worst %.0f" % [roundi(1000.0 / maxf(avg, 0.01)), avg, worst],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# one bar per frame; the line is the 60 fps budget
	var base := size.y - 3.0
	var scale := GRAPH_H / (BUDGET_MS * 3.0)
	for i in BARS:
		var t := _times[i]
		var c := Color(0.45, 0.95, 0.45) if t <= BUDGET_MS * 1.15 else (Color(1.0, 0.8, 0.3) if t <= BUDGET_MS * 2.0 else Color(1.0, 0.35, 0.3))
		var h := minf(t * scale, GRAPH_H)
		draw_rect(Rect2(4.0 + i * 2.0, base - h, 1.5, h), c)
	draw_line(Vector2(4, base - BUDGET_MS * scale), Vector2(w - 4, base - BUDGET_MS * scale), Color(1, 1, 1, 0.35), 1.0)
