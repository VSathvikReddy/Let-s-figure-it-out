extends CanvasLayer
## A black screen that fades in, switches the scene, and fades out again.
## It sits on the window's root (not inside a level), so it survives the
## scene change, then deletes itself. Made by Levels._change_scene().

const FADE_TIME := 0.35

var _black: ColorRect


func _init() -> void:
	layer = 128                                # above everything
	process_mode = Node.PROCESS_MODE_ALWAYS    # works even while the game is paused
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.modulate.a = 0.0
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks during the fade
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_black)


func go_to(scene_path: String) -> void:
	var fade_out := create_tween()
	fade_out.tween_property(_black, "modulate:a", 1.0, FADE_TIME)
	await fade_out.finished

	get_tree().paused = false    # the win screen pauses the game
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame

	var fade_in := create_tween()
	fade_in.tween_property(_black, "modulate:a", 0.0, FADE_TIME)
	await fade_in.finished
	queue_free()
