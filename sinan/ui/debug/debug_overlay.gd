extends Node2D
## F3 debug overlay, drawn in the world: platform navigation links, each
## enemy's state (from its debug_state() if it has one) and the painting
## clarity. Added to the level by hud.gd; invisible until F3 is pressed.

var _font: Font


func _ready() -> void:
	z_index = 200
	visible = false
	_font = ThemeDB.fallback_font
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var nav := get_tree().get_first_node_in_group("nav_graph")
	if nav and nav.has_method("debug_draw"):
		nav.debug_draw(self)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var text := String(e.name)
		if e.has_method("debug_state"):
			text += "  " + str(e.debug_state())
		var p := to_local((e as Node2D).global_position) + Vector2(-30, -60)
		draw_string(_font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
		draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 1.0, 0.7))
	var cam := get_viewport().get_camera_2d()
	if cam:
		var tl := to_local(cam.get_screen_center_position() - get_viewport_rect().size * 0.5 / cam.zoom)
		var c := Paint.clarity(self)
		draw_string(_font, tl + Vector2(20, 120), "clarity %.1f%%   enemies %d" % [c * 100.0,
			get_tree().get_nodes_in_group("enemies").size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.YELLOW)
