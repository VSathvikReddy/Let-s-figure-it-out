extends CanvasLayer
## Pause menu. Esc (the built-in "ui_cancel" action) toggles it.
## The layout is all Control nodes in pause_menu.tscn; this script only pauses
## the game tree and wires up the buttons.
##
## How pausing works: get_tree().paused = true stops every node whose
## process_mode is "Inherit"/"Pausable" (the whole level). This menu's root has
## process_mode = Always, so it keeps running and can unpause.

## Action that opens / closes the menu (Esc by default).
@export var pause_action := &"ui_cancel"
## Fade time for the dark overlay and the panel.
@export var fade_time := 0.15

@onready var root_control: Control = $Root
@onready var resume_button: Button = %ResumeButton
@onready var quit_button: Button = %QuitButton

var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_control.visible = false
	resume_button.pressed.connect(resume)
	quit_button.pressed.connect(_on_quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(pause_action):
		if root_control.visible:
			resume()
		elif not get_tree().paused:  # something else (e.g. the skill tree) owns the pause
			pause()
		get_viewport().set_input_as_handled()


func pause() -> void:
	get_tree().paused = true
	Engine.time_scale = 1.0  # in case we paused during a hit-stop
	# the game hides the OS cursor (custom reticle); show it for the menu
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root_control.visible = true
	root_control.modulate.a = 0.0
	create_tween().tween_property(root_control, "modulate:a", 1.0, fade_time)
	resume_button.grab_focus()  # keyboard / gamepad can navigate the buttons


func resume() -> void:
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before
	root_control.visible = false


func _on_quit() -> void:
	get_tree().quit()
