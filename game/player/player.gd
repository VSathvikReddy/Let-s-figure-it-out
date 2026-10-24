extends CharacterBody2D

signal player_dashed
signal player_dash_collision(node: Node2D)

enum PlayerState { IDLE, MOVING, DASH }
enum PlayerDirection { RIGHT, LEFT }

@export var SPEED := 300.0
@export var JUMP_VELOCITY := -530.0
@export var TERMINAL_FALL_VELOCITY := 1000.0

## Gravity multiplier when jump is released while still rising (short hop)
@export var RELEASE_GRAVITY_MULT := 3.5
## Gravity multiplier near the apex while jump is held (float)
@export var APEX_GRAVITY_MULT := 1.0
## "Near the apex" = |vel.y| below this fraction of JUMP_VELOCITY
@export var APEX_THRESHOLD := 0.3

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
	if not is_on_floor():
		var g := get_gravity().y
		var jump_held := Input.is_action_pressed("jump")

		if velocity.y < 0.0 and not jump_held:
			g *= RELEASE_GRAVITY_MULT   # released while rising: short hop
		elif absf(velocity.y) < absf(JUMP_VELOCITY) * APEX_THRESHOLD and jump_held:
			g *= APEX_GRAVITY_MULT      # held near the top: float

		velocity.y = minf(velocity.y + g * delta, TERMINAL_FALL_VELOCITY)

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

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
	# Only count surfaces facing against the dash (walls), not the floor we slide on.
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().x * _dir_sign() < -0.5:
			player_dash_collision.emit(hit.get_collider() as Node2D)
			_end_dash()
			return

	if dash_duration <= 0.0:
		_end_dash()


func _end_dash() -> void:
	state = PlayerState.IDLE  # _normal_state sets MOVING/IDLE properly next frame
	velocity.x = 0.0
