extends CharacterBody2D

const SPEED = 300.0

func _physics_process(delta: float) -> void:
	# Get movement direction from arrow keys / WASD (ui_left, ui_right, ui_up, ui_down)
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Apply velocity and move
	velocity = direction * SPEED
	move_and_slide()
