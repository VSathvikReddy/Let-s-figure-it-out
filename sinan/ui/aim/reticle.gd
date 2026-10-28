extends Node2D
## Big, high-contrast aim reticle that replaces the OS cursor.
## Normal: crosshair. Painting aim (right mouse): gold ring sized by the depth of
## the layer under it (smaller = farther). The outer arc fills while reloading.

var paint_mode := false
var depth_scale := 1.0   # from paint_picker; only used in paint mode
var has_target := true
var ready_frac := 1.0     # 0 = just fired, 1 = ready
var _t := 0.0
var _pulse := 0.0
## Set every frame by the player (cursor clamped to the aim radius).
var aim_point: Variant = null


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 100
	# hidden AND confined: the invisible OS pointer can't leave the game window
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func fired() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	_t += delta
	_pulse = move_toward(_pulse, 0.0, delta * 6.0)
	var at: Vector2 = aim_point if aim_point != null else get_global_mouse_position()
	global_position = at
	# Keep a constant on-screen size regardless of camera zoom.
	var z := get_viewport().get_canvas_transform().get_scale().x
	scale = Vector2.ONE / maxf(z, 0.01)
	queue_redraw()


func _draw() -> void:
	var outline := Color(0, 0, 0, 0.85)
	var col := Color(1.0, 0.85, 0.3) if paint_mode else Color(1.0, 1.0, 1.0)
	if paint_mode and not has_target:
		col = Color(1.0, 0.35, 0.3)
	var kick := 1.0 + _pulse * 0.35

	if paint_mode:
		var r := lerpf(9.0, 26.0, depth_scale) * kick
		_ring(r, 3.0, col, outline)
		var spin := _t * 2.0
		for i in 4:
			var a := spin + i * TAU / 4.0
			var d := Vector2.from_angle(a)
			_tick(d * (r + 5.0), d * (r + 14.0), col, outline)
		_dot(2.5, col, outline)
	else:
		var gap := 7.0 * kick
		var tick_len := 13.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_tick(d * gap, d * (gap + tick_len), col, outline)
		_dot(2.0, col, outline)

	# reload arc
	if ready_frac < 1.0:
		var rr := 34.0
		draw_arc(Vector2.ZERO, rr, -PI / 2.0, -PI / 2.0 + TAU, 40, Color(0, 0, 0, 0.5), 5.0, true)
		draw_arc(Vector2.ZERO, rr, -PI / 2.0, -PI / 2.0 + TAU * ready_frac, 40, col, 3.0, true)


func _tick(a: Vector2, b: Vector2, col: Color, outline: Color) -> void:
	draw_line(a, b, outline, 6.0, true)
	draw_line(a, b, col, 3.0, true)


func _ring(r: float, w: float, col: Color, outline: Color) -> void:
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, outline, w + 3.0, true)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, w, true)


func _dot(r: float, col: Color, outline: Color) -> void:
	draw_circle(Vector2.ZERO, r + 1.5, outline)
	draw_circle(Vector2.ZERO, r, col)
