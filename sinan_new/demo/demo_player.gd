extends CharacterBody2D

@export var speed := 420.0
@export var play_area := Rect2(-780, -200, 2000, 800)


func _physics_process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	velocity = direction.normalized() * speed
	move_and_slide()
	global_position = global_position.clamp(play_area.position, play_area.end)

	# paint with the Brush (an Area2D), moved to the mouse
	var mouse := get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Painting.paint($Brush, -2.0 * delta, mouse)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		Painting.paint($Brush, 2.0 * delta, mouse)
