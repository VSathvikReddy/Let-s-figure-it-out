extends CharacterBody2D

signal player_dashed
signal player_dash_collision(node: Node2D)

enum PlayerState { IDLE, MOVING, DASH }
enum PlayerDirection { RIGHT, LEFT }

@export var SPEED := 300.0
@export var TERMINAL_FALL_VELOCITY := 1000.0

# --- Thrust-based Jump Settings ---
@export var JUMP_INITIAL_VELOCITY := -250.0
@export var JUMP_THRUST_ACCEL := -1500.0
@export var JUMP_HOLD_DURATION := 0.25

## Gravity multiplier near the apex while jump is held (float)
@export var APEX_GRAVITY_MULT := 0.8
## "Near the apex" = |vel.y| below this threshold
@export var APEX_THRESHOLD := 60.0

@export var JUMP_BUFFER := 0.1
@export var COYOTE_TIME := 0.1

@export var DASH_SPEED := 800.0
@export var DASH_DURATION := 0.15
@export var DASH_COOLDOWN := 1.0

var direction := PlayerDirection.RIGHT
var state := PlayerState.IDLE
var input_x := 0.0

var jump_buffer_timer := 0.0
var coyote_timer := 0.0
var jump_timer := 0.0  # Tracks active upward thrust time

var dash_cool_down := 0.0
var dash_duration := 0.0


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_read_input()

	if state != PlayerState.DASH and _can_dash():
		_start_dash()

	if state == PlayerState.DASH:
		_dash_state()
	else:
		_normal_state(delta)


func _update_timers(delta: float) -> void:
	dash_cool_down -= delta
	dash_duration -= delta
	jump_timer = maxf(0.0, jump_timer - delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer -= delta

	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer -= delta


func _read_input() -> void:
	input_x = Input.get_axis("move_left", "move_right")
	# Don't change facing mid-dash
	if state != PlayerState.DASH and input_x != 0.0:
		direction = PlayerDirection.RIGHT if input_x > 0.0 else PlayerDirection.LEFT


func _dir_sign() -> float:
	return 1.0 if direction == PlayerDirection.RIGHT else -1.0


# ---------------------------------------------------------------- normal

func _normal_state(delta: float) -> void:
	# Handle Jump Initiation
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_INITIAL_VELOCITY
		jump_timer = JUMP_HOLD_DURATION
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# Handle Vertical Movement (Gravity & Thrust)
	if not is_on_floor():
		var g := get_gravity().y
		var jump_held := Input.is_action_pressed("jump")

		# Apply upward thrust if button is held and timer hasn't run out
		if jump_held and jump_timer > 0.0 and velocity.y < 0.0:
			velocity.y += JUMP_THRUST_ACCEL * delta
		
		# Apply apex float if near the top
		elif absf(velocity.y) < APEX_THRESHOLD and jump_held:
			g *= APEX_GRAVITY_MULT

		velocity.y = minf(velocity.y + g * delta, TERMINAL_FALL_VELOCITY)

	velocity.x = input_x * SPEED
	move_and_slide()

	state = PlayerState.MOVING if input_x != 0.0 else PlayerState.IDLE


# ---------------------------------------------------------------- dash

func _can_dash() -> bool:
	return Input.is_action_just_pressed("dash") and dash_cool_down <= 0.0


func _start_dash() -> void:
	state = PlayerState.DASH
	dash_cool_down = DASH_COOLDOWN
	dash_duration = DASH_DURATION
	player_dashed.emit()


func _dash_state() -> void:
	# Fixed velocity, no gravity
	velocity = Vector2(_dir_sign() * DASH_SPEED, 0.0)
	move_and_slide()

	# Collision info only exists AFTER move_and_slide, so check it here.
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().x * _dir_sign() < -0.5:
			player_dash_collision.emit(hit.get_collider() as Node2D)
			_end_dash()
			return

	if dash_duration <= 0.0:
		_end_dash()


func _end_dash() -> void:
	state = PlayerState.IDLE 
	velocity.x = 0.0
