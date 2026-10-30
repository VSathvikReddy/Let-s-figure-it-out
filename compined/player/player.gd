extends CharacterBody2D
## Jetpack player: W/Up thrusts, A/D push sideways, gravity pulls down.
## J opens / closes the veil (Portal), hold attack swings the brush.

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
@export var settle_time: float = 0.5          ## Time to come to rest before the veil opens/closes

## --- Node References ---
@onready var sprite: Sprite2D = $Sprite2D
@onready var left_jetpack: Sprite2D = $Sprite2D/leftthrust
@onready var right_jetpack: Sprite2D = $Sprite2D/rightthrust
@onready var left_particle: GPUParticles2D = $Sprite2D/leftparti
@onready var right_particle: GPUParticles2D = $Sprite2D/rightparti
@onready var portal: Node2D = $Portal
@onready var brush_attack: Node2D = $BrushAttack
@onready var brush_sprite: Sprite2D = $BrushAttack/Brush/Sprite2D
@onready var wand: Sprite2D = $Portal/Wand
@onready var audio_thrust_start: AudioStreamPlayer2D = $AudioThrustStart
@onready var portal_sound: AudioStreamPlayer2D = $PortalSound
@onready var audio_thrust_loop: AudioStreamPlayer2D = $AudioThrustLoop
@onready var body_shape: CollisionShape2D = $Hitbox

## True while settling / during the veil animations: no input, no gravity.
var frozen := false
var gems_collected := 0

## Sent every time a gem is picked up (the win screen listens to it).
signal gem_collected(total: int)
var _veil_busy := false     # a veil open/close is running, ignore J until it ends
var _flash_tween: Tween


func collect_gem(gem: Node2D) -> void:
	gems_collected += 1
	gem_collected.emit(gems_collected)
	gem.queue_free()


func _ready() -> void:
	# Keeps running while the tree is paused, because the veil pauses the world
	# and the player keeps flying inside it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_jetpacks(false)
	wand.visible = false


## Brings the player to rest (velocity and tilt) before a veil animation.
func _settle() -> void:
	frozen = true
	_stop_thrust_fx()
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "velocity", Vector2.ZERO, settle_time)
	tween.tween_property(sprite, "rotation", 0.0, settle_time)
	await tween.finished


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("open_veil") or _veil_busy:
		return
	_veil_busy = true
	portal_sound.play()
	if not portal.active:
		brush_sprite.visible = false
		wand.visible = true
		await portal.activate()
	else:
		await portal.deactivate()
		brush_sprite.visible = true
		wand.visible = false
	_veil_busy = false


func _physics_process(delta: float) -> void:
	# Something else paused the game (a menu): stand still. The veil pauses the
	# tree too, but the player keeps moving inside it.
	if get_tree().paused and not portal.active:
		_stop_thrust_fx()
		return
	if frozen:
		move_and_slide()   # glide to a stop while _settle() eases velocity to zero
		return

	# 1. Read inputs (horizontal & up thrust only)
	var input_x := Input.get_axis("move_left", "move_right")
	var is_thrusting := Input.is_action_pressed("move_up")
	_handle_thruster_audio(Input.is_action_just_pressed("move_up"), is_thrusting)

	# 2. Apply thrust & fast gravity
	velocity.x += input_x * horizontal_thrust * delta
	if is_thrusting:
		velocity.y -= up_thrust * delta
	else:
		velocity.y += fast_gravity * delta

	# 3. Passive drag (opposes all motion)
	velocity.x = move_toward(velocity.x, 0.0, absf(velocity.x) * passive_drag * delta)
	velocity.y = move_toward(velocity.y, 0.0, absf(velocity.y) * passive_drag * delta)

	# 4. Terminal velocity caps
	velocity.x = clampf(velocity.x, -max_horizontal_speed, max_horizontal_speed)
	velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)

	# 5. Visuals
	_update_sprite_tilt(input_x, delta)
	_set_jetpacks(is_thrusting)

	# 6. Move, but never out of the painting
	move_and_slide()
	_stay_inside_level()


## Stops the player at the level bounds (the painting's edges). The whole body
## stays inside, so they can fly right up to every edge but never past it.
func _stay_inside_level() -> void:
	var bounds := get_tree().get_first_node_in_group("level_bounds") as Control
	if bounds == null:
		return
	var half_body: Vector2 = body_shape.shape.size / 2.0
	var inside := bounds.get_global_rect().grow_individual(-half_body.x, -half_body.y, -half_body.x, -half_body.y)
	var clamped := global_position.clamp(inside.position, inside.end)
	if clamped.x != global_position.x:
		velocity.x = 0.0   # hit a side edge
	if clamped.y != global_position.y:
		velocity.y = 0.0   # hit the top or bottom edge
	global_position = clamped


## --- Recoil Helper Function ---
func apply_recoil(impulse: Vector2) -> void:
	velocity += impulse


## --- Thrust Audio Function ---
func _handle_thruster_audio(just_started: bool, active: bool) -> void:
	if just_started:
		audio_thrust_start.play()   # ignition blast, once
	if active and not audio_thrust_loop.playing:
		audio_thrust_loop.play()
	elif not active and audio_thrust_loop.playing:
		audio_thrust_loop.stop()


## --- Visual Helper Functions ---
func _update_sprite_tilt(input_x: float, delta: float) -> void:
	var target_tilt := deg_to_rad(input_x * max_tilt_angle_deg)
	sprite.rotation = lerp_angle(sprite.rotation, target_tilt, 1.0 - exp(-tilt_speed * delta))


func _set_jetpacks(active: bool) -> void:
	left_jetpack.visible = active
	right_jetpack.visible = active
	# only touch `emitting` when it changes, setting it every frame restarts the burst
	if left_particle.emitting != active:
		left_particle.emitting = active
	if right_particle.emitting != active:
		right_particle.emitting = active


func _stop_thrust_fx() -> void:
	_set_jetpacks(false)
	if audio_thrust_loop.playing:
		audio_thrust_loop.stop()


func take_damage(_damage: int) -> void:
	if _flash_tween:
		_flash_tween.kill()   # a new hit restarts the flash instead of fighting the old one
	sprite.modulate = Color(5.0, 5.0, 5.0, 1.0)   # HDR white for an extra bright flash
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
