extends CharacterBody2D

@export var gravity: float = 980.0
@export var ground_friction: float = 1200.0  # Rate at which the player slows down on the ground

# Define the exact 2D acceleration vector for each jetpack in the Inspector
@export var left_jetpack_accel: Vector2 = Vector2(400.0, -1000.0)   # Pushes Up and Right
@export var right_jetpack_accel: Vector2 = Vector2(-400.0, -1000.0) # Pushes Up and Left

@onready var weapon:Weapon= $MelleWepon
@onready var hurt_box:Hurtbox=$Hurtbox



func _ready() -> void:
	hurt_box.damaged.connect(take_dabage)
func _physics_process(delta: float) -> void:
	## 1. Apply Gravity or Ground Friction
	#if not is_on_floor():
		#velocity.y += gravity * delta
	#else:
		#velocity.y = min(velocity.y, 0.0)
		## Apply friction to slow down horizontally when grounded
		#velocity.x = move_toward(velocity.x, 0, ground_friction * delta)
#
	## 2. Handle Input ('A' fires right jetpack, 'D' fires left jetpack)
	#var thrust_force = Vector2.ZERO
#
	#if Input.is_key_pressed(KEY_A):
		#thrust_force += right_jetpack_accel
#
	#if Input.is_key_pressed(KEY_D):
		#thrust_force += left_jetpack_accel
#
	## 3. Apply thrust to velocity
	#velocity += thrust_force * delta
	if Input.is_key_pressed(KEY_SPACE):
		weapon.start_attack()
	# 4. Move the character
	move_and_slide()

func take_dabage():
	pass
