extends CharacterBody2D
## The player: a witch with a jetpack.
##   W / Up      - thrust up (magic sparkles shoot out of her boots)
##   A / D       - push left / right
##   attack      - hold to charge the brush, release to swing (restores the painting)
##   J           - open / close the veil (Portal)
##   Q / right click - summon ghosts: a rune circle fills up, then friendly
##                 ghosts rise, fly to the most damaged part of the painting
##                 and CLEAN it. Getting hit while summoning cancels it.
##
## Looks: the witch's cut-out rig (Visual/Rig) is animated by the
## AnimationPlayer: idle, walk, cast (brush), summon, hurt. Her staff is
## hidden; she holds the brush in her hand instead, and her arm always points
## where the brush points (at the mouse, and along the swing).

const Effects := preload("res://compined/common/effects.gd")

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

@export_group("Summon Ghosts")
@export var ghost_scene: PackedScene
## Keyboard key that summons (right mouse button works too).
@export var summon_key: Key = KEY_Q
## Seconds the rune circle takes to fill up.
@export var summon_time := 1.4
## Seconds before she can summon again.
@export var summon_cooldown := 7.0
## Shorter wait when a summon was interrupted by a hit.
@export var interrupted_summon_cooldown := 2.5
@export var ghosts_per_summon := 2
@export var max_ghosts_alive := 4
## Size of the area each ghost restores, and how much.
@export var ghost_clean_radius := 200.0
@export var ghost_clean_amount := 1
@export var ghost_rise_height := 140.0
@export var ghost_rise_time := 2.4
@export var ghost_glide_time := 1.8
@export var ghost_clean_time := 2.0
@export var ghost_color := Color(1.0, 0.82, 0.86)

## --- Node References ---
@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var arm_pivot: Node2D = $Visual/Rig/ArmPivot      # her shoulder: rotating it turns the arm
@onready var hand: Node2D = $Visual/Rig/ArmPivot/Hand       # where the brush is held
@onready var summon_circle: Node2D = $SummonCircle
## Magic thrust from both boots: glowing motes (Flame) and twinkling stars (Flame/Stars).
@onready var boot_particles: Array[GPUParticles2D] = [
	$Visual/Rig/BackLeg/Flame, $Visual/Rig/BackLeg/Flame/Stars,
	$Visual/Rig/FrontLeg/Flame, $Visual/Rig/FrontLeg/Flame/Stars,
]
@onready var portal: Node2D = $Portal
@onready var brush_attack: Node2D = $BrushAttack
@onready var brush: Node2D = $BrushAttack/Brush            # turned by the brush attack (mouse / swing)
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

# summoning
var summoning := false
var summon_progress := 0.0          # 0..1 while the circle fills
var _summon_wait := 0.0             # cooldown left, in seconds
var _ghosts: Array[Node] = []

# looks
var _facing := 1.0                  # 1 = right, -1 = left
var _visual_scale := Vector2.ONE
var _brush_art_rotation := 0.0      # how the brush picture is turned inside its node
var _hurt_time := 0.0               # plays the hurt animation while > 0


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
	_visual_scale = visual.scale.abs()
	_brush_art_rotation = brush_sprite.rotation
	# run after the brush attack each frame, so the hand uses its newest angle
	process_priority = 10
	summon_circle.visible = false


## Brings the player to rest (velocity and tilt) before a veil animation.
func _settle() -> void:
	frozen = true
	_stop_thrust_fx()
	_cancel_summon(false)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "velocity", Vector2.ZERO, settle_time)
	tween.tween_property(visual, "rotation", 0.0, settle_time)
	await tween.finished


func _unhandled_input(event: InputEvent) -> void:
	if _is_summon_button(event):
		_try_start_summon()
		return
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

	# 6. Summoning ghosts
	_update_summon(delta)

	# 7. Move, but never out of the painting
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
	visual.rotation = lerp_angle(visual.rotation, target_tilt, 1.0 - exp(-tilt_speed * delta))


## Magic from both boots while thrusting.
func _set_jetpacks(active: bool) -> void:
	for particles in boot_particles:
		# only touch `emitting` when it changes, setting it every frame restarts the burst
		if particles.emitting != active:
			particles.emitting = active


func _stop_thrust_fx() -> void:
	_set_jetpacks(false)
	if audio_thrust_loop.playing:
		audio_thrust_loop.stop()


func take_damage(_damage: int) -> void:
	if _flash_tween:
		_flash_tween.kill()   # a new hit restarts the flash instead of fighting the old one
	visual.modulate = Color(5.0, 5.0, 5.0, 1.0)   # HDR white for an extra bright flash
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", Color.WHITE, 0.15)
	_hurt_time = 0.3
	_cancel_summon(true)   # a hit breaks her concentration


# --- summoning ghosts ------------------------------------------------------

func _is_summon_button(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == summon_key
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	return false


func _try_start_summon() -> void:
	if summoning or frozen or portal.active or ghost_scene == null:
		return
	if _summon_wait > 0.0 or _ghosts_alive() >= max_ghosts_alive:
		return
	summoning = true
	summon_progress = 0.0


func _update_summon(delta: float) -> void:
	_summon_wait = maxf(_summon_wait - delta, 0.0)
	if not summoning:
		return
	summon_progress += delta / summon_time
	if summon_progress >= 1.0:
		_finish_summon()


## The circle is full: the ghosts rise out of it.
func _finish_summon() -> void:
	summoning = false
	_summon_wait = summon_cooldown
	var circle_at := summon_circle.global_position
	Effects.burst(summon_circle, 20, ghost_color, 0.6, 60.0, 160.0, 3.0, 6.0)
	for i in ghosts_per_summon:
		if _ghosts_alive() >= max_ghosts_alive:
			break
		var ghost = ghost_scene.instantiate()
		ghost.start_delay = i * 0.25
		ghost.rise_height = ghost_rise_height * randf_range(0.85, 1.15)
		ghost.rise_time = ghost_rise_time
		ghost.glide_time = ghost_glide_time
		ghost.clean_time = ghost_clean_time
		ghost.clean_radius = ghost_clean_radius
		ghost.clean_amount = ghost_clean_amount
		ghost.ghost_color = ghost_color
		# side by side over the circle
		var spread := (i - (ghosts_per_summon - 1) * 0.5) * 24.0
		ghost.position = circle_at + Vector2(spread, -10)
		get_tree().current_scene.add_child(ghost)
		_ghosts.append(ghost)


## Stops a summon that is still filling. `broken` = it was interrupted by a hit
## (sparks fly and the wait is shorter than a full cooldown).
func _cancel_summon(broken: bool) -> void:
	if not summoning:
		return
	summoning = false
	if broken:
		_summon_wait = interrupted_summon_cooldown
		Effects.burst(summon_circle, 22, Color(1.0, 0.36, 0.42), 0.5, 150.0, 380.0, 2.0, 4.0)


func _ghosts_alive() -> int:
	_ghosts = _ghosts.filter(func(ghost): return is_instance_valid(ghost))
	return _ghosts.size()


# --- looks -----------------------------------------------------------------

func _process(delta: float) -> void:
	_hurt_time = maxf(_hurt_time - delta, 0.0)
	var attacking: bool = brush_attack.state != 0   # brush charging or swinging

	# she always faces the mouse, because her hand points at it
	var to_mouse := get_global_mouse_position().x - global_position.x
	if absf(to_mouse) > 2.0:
		_facing = signf(to_mouse)
	visual.scale = Vector2(_facing * _visual_scale.x, _visual_scale.y)

	_point_arm_and_hold_brush()

	summon_circle.visible = summoning
	summon_circle.progress = summon_progress

	_play_animation(attacking)


## Turns her arm so the hand points the way the brush points, and puts the
## brush picture in her hand. The brush attack itself (the arc and what it
## hits) still works around her body, exactly as before.
func _point_arm_and_hold_brush() -> void:
	var brush_direction := Vector2.from_angle(brush.global_rotation)
	# where to point, in the rig's own space (this handles her facing left/right)
	var rig := arm_pivot.get_parent() as Node2D
	var point_at := rig.to_local(global_position + brush_direction * 200.0)
	var shoulder_to_target := point_at - arm_pivot.position
	# the hand sits at an angle on the arm, so subtract that angle
	arm_pivot.rotation = shoulder_to_target.angle() - hand.position.angle()

	brush_sprite.global_position = hand.global_position
	brush_sprite.global_rotation = brush.global_rotation + _brush_art_rotation


## idle / walk while flying, cast with the brush, summon, hurt.
func _play_animation(attacking: bool) -> void:
	var wanted := &"idle"
	if _hurt_time > 0.0:
		wanted = &"hurt"
	elif summoning:
		wanted = &"summon"
	elif attacking:
		wanted = &"cast"
	elif absf(velocity.x) > 10.0:
		wanted = &"walk"
	if anim.current_animation != wanted:
		anim.play(wanted)
