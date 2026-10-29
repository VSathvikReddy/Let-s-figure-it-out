extends CharacterBody2D

@export var speed := 420.0


func _physics_process(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	velocity = direction.normalized() * speed
	move_and_slide()
	# stay on the painting: inside what the camera can show (the body is 36 x 72,
	# its origin at the feet)
	var edges: Rect2 = $Camera2D.edges
	global_position = global_position.clamp(edges.position + Vector2(18, 72), edges.end - Vector2(18, 0))

	# left mouse: repair with the Brush (an Area2D), moved to the mouse,
	# 2 detail levels per second. (Right mouse is the Wand - see wand.gd.)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Painting.paint($Brush, -2.0 * delta, get_global_mouse_position())
