extends CharacterBody2D
## The player: a witch with a jetpack.
##   W / Up      - thrust up (magic sparkles shoot out of her boots)
##   A / D       - push left / right
##   attack      - hold to charge the brush, release to swing (restores the painting)
##   Q / right click - use the POWER-UP she is holding (top-right corner).
##                 She holds one at a time; picking up a token replaces it.
##                   Dash   - a quick burst toward the mouse, unhurtable during it
##                   Ghost  - HOLD Q: she rises into a floating stance, a rune
##                            circle fills, then friendly ghosts clean the
##                            painting. Letting go early fizzles it (the power-up
##                            is kept); a hit breaks the stance. Not in the veil.
##                   Trail  - for a while, the painting is restored where she flies
##                   Shield - for a while, a bubble blocks every hit
##                   Veil   - opens the veil
##   J           - closes the veil (opening it needs the Veil power-up)
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

@export_group("Health")
@export var max_health := 10
## Seconds she cannot be hurt again after a hit (so one blast is one hit).
@export var invincible_time := 0.6

@export_group("Falling")
## How far below the painting she must fall before she is lost (px).
@export var fall_out_distance := 250.0

@export_group("Summon Ghosts")
@export var ghost_scene: PackedScene
## Keyboard key to HOLD for summoning (holding the right mouse button works too).
@export var summon_key: Key = KEY_Q
## Seconds the key must be held while the rune circle fills up.
@export var summon_time := 1.4
## Seconds before she can summon again.
@export var summon_cooldown := 7.0
## Wait after a hit broke her stance.
@export var interrupted_summon_cooldown := 2.5
## Wait after letting go of the key too early.
@export var released_summon_cooldown := 0.5
## How many ghosts one summon makes: a random number between these two.
@export_range(1, 16) var min_ghosts_per_summon := 6
@export_range(1, 16) var max_ghosts_per_summon := 8
## Seconds between one ghost appearing and the next (they come out one at a time).
@export var ghost_spawn_interval := 0.45
## How far from her the ghosts appear, in a ring around her (px).
@export var ghost_spawn_distance := 90.0
## Most ghosts that can be out at the same time.
@export_range(1, 32) var max_ghosts_alive := 16
## Size of the area each ghost restores (px), and how much detail it brings back.
@export var ghost_clean_radius := 320.0
@export var ghost_clean_amount := 1
## Size of each ghost (px).
@export var ghost_size := 20.0
@export var ghost_rise_height := 140.0
@export var ghost_rise_time := 2.4
@export var ghost_glide_time := 1.8
@export var ghost_clean_time := 2.0
@export var ghost_color := Color(1.0, 0.82, 0.86)

@export_group("Power-ups")
@export var dash_speed := 950.0
@export var dash_time := 0.22             ## seconds the dash lasts
@export var shield_time := 6.0            ## seconds the shield lasts
@export var trail_time := 6.0             ## seconds the magic trail lasts
@export var trail_radius := 80.0          ## width of the restored band, in px
@export var trail_spacing := 40.0         ## px flown between two restore stamps
@export var trail_amount := 1             ## detail levels each stamp brings back

@export_group("Summon Stance")
## How fast she rises when the stance starts (px per second).
@export var float_rise_speed := 60.0
## Gentle up-and-down while floating: height (px per second) and speed (bobs per second).
@export var float_bob_height := 18.0
@export var float_bob_speed := 1.2
## How hard a hit throws her out of the stance.
@export var stance_break_knockback := 300.0

## --- Node References ---
@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var arm_pivot: Node2D = $Visual/Rig/ArmPivot      # her shoulder: rotating it turns the arm
@onready var hand: Node2D = $Visual/Rig/ArmPivot/Hand       # where the brush is held
@onready var summon_circle: Node2D = $SummonCircle
@onready var summon_aura: GPUParticles2D = $SummonAura      # magic rising around her while summoning
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
signal gem_collected(total: int, picture: Texture2D)
## Sent once when she falls out of the bottom of the painting.
signal fell_out
## Sent when her health changes (the health bar listens to it).
signal health_changed(current: float, maximum: float)
## Sent once when her health reaches zero.
signal died
## Sent when the held power-up changes (picture null = she holds none).
signal power_changed(picture: Texture2D, power_name: String)

const ShieldBubble := preload("res://compined/powerup/shield_bubble.gd")
var _fell := false
var health := 0
var _invincible := 0.0      # seconds of invincibility left
## Set by the level from its difficulty: hits hurt this many times more.
var damage_taken_multiplier := 1.0
var _veil_busy := false     # a veil open/close is running, ignore J until it ends
var _flash_tween: Tween

# summoning
var summoning := false
var summon_progress := 0.0          # 0..1 while the circle fills
var _summon_wait := 0.0             # cooldown left, in seconds
var _ghosts: Array[Node] = []

# power-ups
var collected_power_up = null       # the PowerUp.PowerType she holds, or null
var _dash_left := 0.0
var _dash_direction := Vector2.RIGHT
var _trail_left := 0.0
var _trail_last_stamp := Vector2.INF
var _shield: Node2D

# looks
var _facing := 1.0                  # 1 = right, -1 = left
var _visual_scale := Vector2.ONE
var _brush_art_rotation := 0.0      # how the brush picture is turned inside its node
var _hurt_time := 0.0               # plays the hurt animation while > 0


func collect_gem(gem: Node2D) -> void:
	gems_collected += 1
	var sprite := gem.get_node_or_null("Sprite2D") as Sprite2D   # the gem's picture, for the counter
	gem_collected.emit(gems_collected, sprite.texture if sprite else null)
	gem.queue_free()


func _ready() -> void:
	# Keeps running while the tree is paused, because the veil pauses the world
	# and the player keeps flying inside it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	health = max_health
	_set_jetpacks(false)
	wand.visible = false
	_visual_scale = visual.scale.abs()
	_brush_art_rotation = brush_sprite.rotation
	# run after the brush attack each frame, so the hand uses its newest angle
	process_priority = 10
	summon_circle.visible = false
	_shield = ShieldBubble.new()
	add_child(_shield)


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
		use_power()
		return
	# J only closes the veil; opening it needs the Veil power-up
	if event.is_action_pressed("open_veil") and portal.active:
		_toggle_veil()


## Opens the veil if it is closed, closes it if it is open.
func _toggle_veil() -> void:
	if _veil_busy:
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
	if summoning:
		_float_while_summoning(delta)
		_update_summon(delta)
		move_and_slide()
		_stay_inside_level()
		return
	_update_power_ups(delta)
	if _dash_left > 0.0:
		_dash(delta)
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


## The painting's LEFT, RIGHT and TOP edges stop her (the whole body stays
## inside). The BOTTOM edge does not: she can fall out of the painting. The
## camera stays on the painting and does not follow, and once she has fallen
## `fall_out_distance` below it she is lost (fell_out).
func _stay_inside_level() -> void:
	var bounds := get_tree().get_first_node_in_group("level_bounds") as Control
	if bounds == null:
		return
	var area := bounds.get_global_rect()
	var half_body: Vector2 = body_shape.shape.size / 2.0
	var left := area.position.x + half_body.x
	var right := area.end.x - half_body.x
	var top := area.position.y + half_body.y
	if global_position.x < left or global_position.x > right:
		global_position.x = clampf(global_position.x, left, right)
		velocity.x = 0.0   # hit a side edge
	if global_position.y < top:
		global_position.y = top
		velocity.y = 0.0   # hit the top edge
	if global_position.y - half_body.y > area.end.y + fall_out_distance and not _fell:
		_fell = true
		_stop_thrust_fx()
		fell_out.emit()


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


func take_damage(damage: int) -> void:
	if _invincible > 0.0 or health <= 0:
		return
	if _shield.time_left > 0.0:
		_shield.flash()   # the shield takes the hit
		_invincible = invincible_time
		return
	health = maxi(health - maxi(1, roundi(damage * damage_taken_multiplier)), 0)
	_invincible = invincible_time
	health_changed.emit(health, max_health)
	if health == 0:
		died.emit()
	if _flash_tween:
		_flash_tween.kill()   # a new hit restarts the flash instead of fighting the old one
	visual.modulate = Color(5.0, 5.0, 5.0, 1.0)   # HDR white for an extra bright flash
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", Color.WHITE, 0.15)
	_hurt_time = 0.3
	_cancel_summon(true)   # a hit breaks her stance


# --- summoning ghosts ------------------------------------------------------

func _is_summon_button(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == summon_key
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	return false


## True while the summon key (or the right mouse button) is held down.
func _summon_button_held() -> bool:
	return Input.is_physical_key_pressed(summon_key) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _try_start_summon() -> void:
	# needs the Ghost power-up; not inside the veil or while it opens or closes
	if collected_power_up != PowerUp.PowerType.GHOST:
		return
	if summoning or frozen or portal.active or _veil_busy or ghost_scene == null:
		return
	if _summon_wait > 0.0 or _ghosts_alive() >= max_ghosts_alive:
		return
	summoning = true
	summon_progress = 0.0


## The summon stance: no thrust, no gravity. She drifts to a stop, rises a
## little, then bobs gently in the air while the circle fills. Letting go of
## the key before it is full fizzles the summon.
func _float_while_summoning(delta: float) -> void:
	_stop_thrust_fx()
	if not _summon_button_held():
		_cancel_summon(false)
		return
	var time_floating := summon_progress * summon_time
	var bob := cos(time_floating * TAU * float_bob_speed) * float_bob_height
	var wanted_vy := -float_rise_speed * (1.0 - summon_progress) + bob
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	velocity.y = lerpf(velocity.y, wanted_vy, 1.0 - exp(-6.0 * delta))
	visual.rotation = lerp_angle(visual.rotation, 0.0, 1.0 - exp(-8.0 * delta))


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
	_use_up_power()   # the Ghost power-up is spent only when the summon succeeds
	Effects.burst(summon_circle, 10, ghost_color, 0.5, 40.0, 110.0, 2.0, 4.0)
	var count := randi_range(min_ghosts_per_summon, maxi(min_ghosts_per_summon, max_ghosts_per_summon))
	var first_angle := randf() * TAU
	for i in count:
		if _ghosts_alive() >= max_ghosts_alive:
			break
		var ghost = ghost_scene.instantiate()
		ghost.start_delay = i * ghost_spawn_interval   # one at a time
		ghost.rise_height = ghost_rise_height * randf_range(0.85, 1.15)
		ghost.rise_time = ghost_rise_time
		ghost.glide_time = ghost_glide_time
		ghost.clean_time = ghost_clean_time
		ghost.clean_radius = ghost_clean_radius
		ghost.clean_amount = ghost_clean_amount
		ghost.ghost_color = ghost_color
		ghost.ghost_radius = ghost_size
		# spread evenly in a ring around her, each a little off so it looks natural
		var angle := first_angle + TAU * i / count + randf_range(-0.2, 0.2)
		var distance := ghost_spawn_distance * randf_range(0.85, 1.15)
		ghost.position = global_position + Vector2.from_angle(angle) * distance
		get_tree().current_scene.add_child(ghost)
		_ghosts.append(ghost)


## Stops a summon that is still filling.
##   broken = true  - a hit broke her stance: the circle shatters and she is
##                    thrown back.
##   broken = false - she let go of the key (or the veil opened): it fizzles.
func _cancel_summon(broken: bool) -> void:
	if not summoning:
		return
	summoning = false
	if broken:
		_summon_wait = interrupted_summon_cooldown
		velocity = Vector2(-_facing * stance_break_knockback, -stance_break_knockback * 0.6)
		Effects.burst(summon_circle, 18, Color(1.0, 0.36, 0.42), 0.5, 140.0, 320.0, 2.0, 4.0)
	else:
		_summon_wait = released_summon_cooldown
		Effects.burst(summon_circle, 8, Color(1.0, 0.6, 0.9, 0.6), 0.4, 30.0, 80.0, 2.0, 3.0)


func _ghosts_alive() -> int:
	_ghosts = _ghosts.filter(func(ghost): return is_instance_valid(ghost))
	return _ghosts.size()


# --- power-ups -------------------------------------------------------------

## Called by a PowerUp token she touches: she now holds this ability (it
## replaces the one she had).
func pick_up_power_up(type: PowerUp.PowerType, picture: Texture2D = null) -> void:
	if summoning:
		_cancel_summon(false)   # swapping away from Ghost mid-summon
	collected_power_up = type
	power_changed.emit(picture, PowerUp.NAMES[type])
	Effects.burst(self, 14, Color(1.0, 0.9, 0.6), 0.4, 60.0, 150.0, 2.0, 4.0)


## Q: use the held power-up.
func use_power() -> void:
	if collected_power_up == null or frozen:
		return
	match collected_power_up:
		PowerUp.PowerType.GHOST:
			_try_start_summon()       # used up when the summon finishes
		PowerUp.PowerType.VEIL:
			if not portal.active and not _veil_busy:
				_use_up_power()
				_toggle_veil()
		PowerUp.PowerType.DASH:
			_use_up_power()
			_start_dash()
		PowerUp.PowerType.SHIELD:
			_use_up_power()
			_shield.time_left = shield_time
		PowerUp.PowerType.TRAIL:
			_use_up_power()
			_trail_left = trail_time
			_trail_last_stamp = Vector2.INF


func _use_up_power() -> void:
	collected_power_up = null
	power_changed.emit(null, "")


func _start_dash() -> void:
	_dash_direction = global_position.direction_to(get_global_mouse_position())
	if _dash_direction == Vector2.ZERO:
		_dash_direction = Vector2(_facing, 0)
	_dash_left = dash_time
	_invincible = maxf(_invincible, dash_time + 0.1)   # can't be hurt while dashing
	Effects.burst(self, 20, Color(0.55, 0.85, 1.0), 0.4, 80.0, 200.0, 3.0, 6.0)


## While dashing: straight and fast toward where she aimed, leaving afterimages.
func _dash(delta: float) -> void:
	_dash_left -= delta
	velocity = _dash_direction * dash_speed
	Effects.burst(self, 3, Color(0.55, 0.85, 1.0, 0.7), 0.3, 10.0, 40.0, 3.0, 6.0)
	move_and_slide()
	_stay_inside_level()
	if _dash_left <= 0.0:
		velocity *= 0.35   # comes out of the dash with some speed left


## Counts down the shield and the trail; the trail restores the painting behind her.
func _update_power_ups(delta: float) -> void:
	_shield.time_left = maxf(_shield.time_left - delta, 0.0)
	if _trail_left <= 0.0:
		return
	_trail_left -= delta
	if _trail_last_stamp == Vector2.INF or global_position.distance_to(_trail_last_stamp) >= trail_spacing:
		_trail_last_stamp = global_position
		Effects.paint_circle(self, global_position, trail_radius, trail_amount)
		Effects.burst(self, 4, Color(1.0, 0.85, 0.4), 0.5, 20.0, 60.0, 2.0, 4.0)


# --- looks -----------------------------------------------------------------

func _process(delta: float) -> void:
	_hurt_time = maxf(_hurt_time - delta, 0.0)
	_invincible = maxf(_invincible - delta, 0.0)
	var attacking: bool = brush_attack.state != 0   # brush charging or swinging

	# she always faces the mouse, because her hand points at it
	var to_mouse := get_global_mouse_position().x - global_position.x
	if absf(to_mouse) > 2.0:
		_facing = signf(to_mouse)
	visual.scale = Vector2(_facing * _visual_scale.x, _visual_scale.y)

	_point_arm_and_hold_brush()

	summon_circle.visible = summoning
	if summon_aura.emitting != summoning:
		summon_aura.emitting = summoning
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
