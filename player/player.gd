extends CharacterBody2D

## --- Movement & Thruster Parameters ---
@export_group("Thruster Forces")
@export var horizontal_thrust: float = 600.0
@export var up_thrust: float = 800.0

@export_group("Limits & Gravity")
@export var max_horizontal_speed: float = 250.0
@export var max_rise_speed: float = 300.0
@export var max_fall_speed: float = 400.0     ## Fast terminal fall velocity
@export var fast_gravity: float = 900.0       ## Strong gravity pulling downward
@export var passive_drag: float = 1.8         ## Opposes motion in all directions

@export_group("Visual FX")
@export var max_tilt_angle_deg: float = 12.0
@export var tilt_speed: float = 8.0

## --- Node References ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var left_jetpack: Sprite2D = $Sprite2D/leftthrust
@onready var right_jetpack: Sprite2D = $Sprite2D/rightthrust
@onready var left_particle: GPUParticles2D = $Sprite2D/leftparti
@onready var right_particle: GPUParticles2D = $Sprite2D/rightparti

func _ready() -> void:
	_set_jetpacks_visible(false)

func _physics_process(delta: float) -> void:
	# 1. Read Inputs (Horizontal & Up Thrust Only)
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	
	var is_thrusting_up = Input.is_action_pressed("ui_up")
	
	# 2. Apply Thrust & Fast Gravity Forces
	if input_vector.x != 0:
		velocity.x += input_vector.x * horizontal_thrust * delta
		
	if is_thrusting_up:
		velocity.y -= up_thrust * delta
	else:
		# Apply heavy gravity when not actively thrusting up
		velocity.y += fast_gravity * delta

	# 3. Apply Passive Drag (Opposes all motion)
	velocity.x = move_toward(velocity.x, 0.0, abs(velocity.x) * passive_drag * delta)
	velocity.y = move_toward(velocity.y, 0.0, abs(velocity.y) * passive_drag * delta)

	# 4. Clamp Speeds (Terminal Velocity Caps)
	velocity.x = clamp(velocity.x, -max_horizontal_speed, max_horizontal_speed)
	velocity.y = clamp(velocity.y, -max_rise_speed, max_fall_speed)

	# 5. Visual Updates
	_update_sprite_tilt(input_vector.x, delta)
	_set_jetpacks_visible(is_thrusting_up)
	if is_thrusting_up == false:
		left_particle.emitting = false
		right_particle.emitting = false

	# 6. Execute Physics Movement
	move_and_slide()

## --- Recoil Helper Function ---
func apply_recoil(impulse: Vector2) -> void:
	velocity += impulse

## --- Visual Helper Functions ---
func _update_sprite_tilt(input_x: float, delta: float) -> void:
	var target_tilt = deg_to_rad(input_x * max_tilt_angle_deg)
	sprite.rotation = lerp_angle(sprite.rotation, target_tilt, tilt_speed * delta)

func _set_jetpacks_visible(active: bool) -> void:
	if left_jetpack:
		left_jetpack.visible = active
		left_particle.emitting = true
	if right_jetpack:
		right_jetpack.visible = active
		right_particle.emitting = true
