extends CharacterBody2D
## Celeste-style platformer controller with two weapon slots.
## Controls: A/D or arrows move, Space jump, Shift dash, S/Down fast-fall,
## mouse aims, left click (or F) fires, R cycles weapon slots,
## hold right mouse to aim into the painting (feet plant, shots shrink with depth).

const FxLib := preload("res://sinan/fx/fx_lib.gd")
const PaintPicker := preload("res://sinan/fx/paint_picker.gd")
const Reticle := preload("res://sinan/fx/reticle.gd")
const AimGuide := preload("res://sinan/fx/aim_guide.gd")
const Weapon := preload("res://sinan/weapons/weapon.gd")

## Weapon scenes (root must use a script extending sinan/weapons/weapon.gd).
@export var weapon_slot_1: PackedScene = preload("res://sinan/weapons/rocket_launcher.tscn")
@export var weapon_slot_2: PackedScene = preload("res://sinan/weapons/pistol.tscn")
@export var weapon_slot_3: PackedScene = preload("res://sinan/weapons/orb_staff.tscn")
@export var weapon_slot_4: PackedScene = preload("res://sinan/weapons/brush_staff.tscn")
## Where the weapon is held, in player-local units.
@export var weapon_hold := Vector2(0, 10)
## The camera never shows anything outside this node's rectangle (a Control
## such as the frame's NinePatchRect, or a Sprite2D). Empty = no limits.
@export var camera_bounds: NodePath = ^"../frame/NinePatchRect"
## Pull the camera limits inwards (+) or let it see past the bounds (-), in px.
@export var camera_bounds_margin := 0.0

# run
const MAX_RUN := 380.0
const RUN_ACCEL := 3400.0
const GROUND_FRICTION := 3800.0
const AIR_FRICTION := 1100.0
const AIR_ACCEL_MULT := 0.65
const TURN_MULT := 1.4
const OVER_MAX_DECEL := 2400.0  # bleeds off extra speed from dash/knockback

# jump / gravity
const GRAVITY := 3000.0
const JUMP_VELOCITY := -820.0
const JUMP_BOOST := 40.0
const JUMP_CUT := 0.45
const APEX_THRESHOLD := 120.0
const APEX_GRAVITY_MULT := 0.5
const MAX_FALL := 1100.0
const FAST_FALL := 1500.0
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const CORNER_PUSH := 8

# dash
const DASH_SPEED := 950.0
const DASH_TIME := 0.13
const DASH_END_SPEED := 480.0
const HYPER_SPEED := 620.0  # jump out of a grounded dash

# knockback (recoil values live on each weapon scene)
const KNOCK_TIME := 0.3
const KNOCK_CONTROL := 0.35
const BLAST_KNOCK := 1300.0
const SWAP_DELAY := 0.2

# painting aim
const PLANT_FEET_WHILE_AIMING := true

# juice
const SQ_K := 320.0
const SQ_D := 14.0
const SPRITE_HALF := 64.0  # half the sprite height, keeps feet planted when squashing
const FEET := Vector2(0, 18.6)
const SHAKE_MAX := 40.0
const RESPAWN_Y := 1400.0

var _coyote := 0.0
var _buffer := 0.0
var _knock := 0.0
var _dash_time := 0.0
var _dash_dir := 1.0
var _dashes := 1
var _dash_cd := 0.0
var _ghost_t := 0.0
var _facing := 1.0
var _was_on_floor := false
var _fall_speed := 0.0
var _fire_cd := 0.0
var _fire_cd_max := 0.5
var _weapons: Array[Weapon] = []
var _current := 0
var _aim := Vector2.RIGHT
var _trauma := 0.0
var _sq := Vector2.ONE
var _sq_vel := Vector2.ZERO
var _spawn := Vector2.ZERO
var _painting := false     # right mouse held
var _pick := {}            # layer under the reticle (paint_picker.pick)

@onready var _sprite: Sprite2D = $Sprite2D
var _cam: Camera2D
var _guide: AimGuide
var _reticle: Reticle


func _ready() -> void:
	add_to_group("player")
	_ensure_inputs()
	_spawn = global_position
	_cam = get_node_or_null("Camera2D")
	_apply_camera_limits.call_deferred()

	for slot in [weapon_slot_1, weapon_slot_2, weapon_slot_3, weapon_slot_4]:
		if slot == null:
			continue
		var w := slot.instantiate() as Weapon
		if w == null:
			push_warning("Weapon slot scene must use a script extending sinan/weapons/weapon.gd")
			continue
		w.position = weapon_hold
		w.z_index = 1
		w.visible = _weapons.is_empty()
		add_child(w)
		_weapons.append(w)

	_guide = AimGuide.new()
	add_child(_guide)

	_reticle = Reticle.new()
	add_child(_reticle)

	var lamp := PointLight2D.new()
	lamp.texture = FxLib.glow()
	lamp.color = Color(1.0, 0.9, 0.75)
	lamp.energy = 0.6
	lamp.texture_scale = 14.0
	add_child(lamp)


func _ensure_inputs() -> void:
	# project.godot already has jump/move_left/move_right/dash; add the rest at runtime.
	_add_action("fire", [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_F)])
	_add_action("move_down", [_key(KEY_S), _key(KEY_DOWN)])
	_add_action("switch_weapon", [_key(KEY_R)])
	_add_action("aim_paint", [_mouse(MOUSE_BUTTON_RIGHT)])


## Clamp the camera to the bounds node's on-screen rectangle (handles rotation,
## e.g. the frame is flipped 180°).
func _apply_camera_limits() -> void:
	if _cam == null or camera_bounds.is_empty():
		return
	var n := get_node_or_null(camera_bounds)
	var rect: Rect2
	if n is Control:
		rect = Rect2(Vector2.ZERO, n.size)
	elif n is Sprite2D:
		rect = n.get_rect()
	else:
		push_warning("camera_bounds must point to a Control or Sprite2D")
		return
	var xf: Transform2D = n.get_global_transform()
	var bounds := Rect2(xf * rect.position, Vector2.ZERO)
	for c in [rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)]:
		bounds = bounds.expand(xf * c)
	bounds = bounds.grow(-camera_bounds_margin)
	_cam.limit_left = floori(bounds.position.x)
	_cam.limit_top = floori(bounds.position.y)
	_cam.limit_right = ceili(bounds.end.x)
	_cam.limit_bottom = ceili(bounds.end.y)
	_cam.limit_smoothed = true
	_cam.reset_smoothing()


static func _add_action(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for e in events:
		InputMap.action_add_event(action, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


# ---------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	var dir_x := Input.get_axis("move_left", "move_right")
	var on_floor := is_on_floor()
	_painting = Input.is_action_pressed("aim_paint")
	if _painting and PLANT_FEET_WHILE_AIMING:
		dir_x = 0.0

	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_knock = maxf(_knock - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_buffer = JUMP_BUFFER
	if on_floor:
		_coyote = COYOTE
		if _dash_time <= 0.0 and _dash_cd <= 0.0:
			_dashes = 1
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	if dir_x != 0.0:
		_facing = signf(dir_x)

	if on_floor and not _was_on_floor:
		_on_land(_fall_speed)
	_was_on_floor = on_floor

	if Input.is_action_just_pressed("dash") and _dashes > 0 and _dash_time <= 0.0:
		_start_dash(dir_x)

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity = Vector2(_dash_dir * DASH_SPEED, 0.0)
		_ghost_t -= delta
		if _ghost_t <= 0.0:
			_ghost_t = 0.025
			_spawn_ghost()
		if _buffer > 0.0 and _coyote > 0.0:
			_dash_time = 0.0
			_jump(dir_x)
			velocity.x = _dash_dir * HYPER_SPEED
		elif _dash_time <= 0.0:
			velocity.x = _dash_dir * DASH_END_SPEED
	else:
		_run(dir_x, on_floor, delta)
		if _buffer > 0.0 and _coyote > 0.0:
			_jump(dir_x)
		if Input.is_action_just_released("jump") and velocity.y < 0.0:
			velocity.y *= JUMP_CUT
		if not on_floor:
			var g := GRAVITY
			if absf(velocity.y) < APEX_THRESHOLD and Input.is_action_pressed("jump"):
				g *= APEX_GRAVITY_MULT
			var max_fall := FAST_FALL if Input.is_action_pressed("move_down") else MAX_FALL
			velocity.y = move_toward(velocity.y, max_fall, g * delta)

	_corner_correct(delta)
	_fall_speed = velocity.y
	move_and_slide()

	var mouse := get_global_mouse_position()
	_pick = PaintPicker.pick(get_parent(), mouse) if _painting else {}

	if Input.is_action_just_pressed("switch_weapon"):
		_switch_weapon()
	var w := _weapon()
	if w:
		if Input.is_action_just_pressed("fire") and _fire_cd <= 0.0:
			_fire_cd = w.reload_time
			_fire_cd_max = maxf(w.reload_time, 0.001)
			w.fire(self, _aim, _painting, _pick, mouse)
			_reticle.fired()
		var ready_shot := _fire_cd <= 0.0
		if _painting:
			var s: float = _pick.get("scale", 0.3)
			# Ring = this weapon's distortion radius (layers are drawn 1:1).
			_guide.update_paint(w.muzzle_global(), mouse, s, w.paint_arc, ready_shot, w.impact_radius)
		else:
			w.update_preview(_guide, _aim, get_rid(), ready_shot)

	if global_position.y > RESPAWN_Y:
		global_position = _spawn
		velocity = Vector2.ZERO


func _run(dir_x: float, on_floor: bool, delta: float) -> void:
	var rate: float
	if dir_x == 0.0:
		rate = GROUND_FRICTION if on_floor else AIR_FRICTION
	elif absf(velocity.x) > MAX_RUN and signf(velocity.x) == signf(dir_x):
		rate = OVER_MAX_DECEL
	else:
		rate = RUN_ACCEL * (1.0 if on_floor else AIR_ACCEL_MULT)
		if signf(velocity.x) != signf(dir_x):
			rate *= TURN_MULT
	if _knock > 0.0:
		rate *= KNOCK_CONTROL
	velocity.x = move_toward(velocity.x, dir_x * MAX_RUN, rate * delta)


func _jump(dir_x: float) -> void:
	velocity.y = JUMP_VELOCITY
	velocity.x += dir_x * JUMP_BOOST
	_buffer = 0.0
	_coyote = 0.0
	_sq = Vector2(0.68, 1.38)
	FxLib.dust(get_parent(), global_position + FEET, 6, 0.8)


func _start_dash(dir_x: float) -> void:
	_dash_dir = signf(dir_x) if dir_x != 0.0 else _facing
	_dash_time = DASH_TIME
	_dash_cd = DASH_TIME + 0.1
	_dashes = 0
	_ghost_t = 0.0
	_sq = Vector2(1.45, 0.65)
	add_trauma(0.1)
	FxLib.dust(get_parent(), global_position + FEET, 8, 1.4)


func _on_land(vy: float) -> void:
	if vy < 250.0:
		return
	var s := clampf(vy / 1400.0, 0.0, 1.0)
	_sq = Vector2(1.0 + 0.45 * s, 1.0 - 0.4 * s)
	FxLib.dust(get_parent(), global_position + FEET, 4 + int(8.0 * s), 0.6 + s)
	if vy > 900.0:
		add_trauma(0.15)


## Nudge sideways around ceiling corners instead of bonking (Celeste trick).
func _corner_correct(delta: float) -> void:
	if velocity.y >= 0.0:
		return
	var motion := Vector2(0.0, velocity.y * delta)
	if not test_move(global_transform, motion):
		return
	for i in range(1, CORNER_PUSH + 1):
		for s in [-1.0, 1.0]:
			if not test_move(global_transform.translated(Vector2(i * s, 0.0)), motion):
				global_position.x += i * s
				return


# ---------------------------------------------------------------- weapons

func _weapon() -> Weapon:
	return _weapons[_current] if _current < _weapons.size() else null


func _switch_weapon() -> void:
	if _weapons.size() < 2:
		return
	_weapons[_current].visible = false
	_current = (_current + 1) % _weapons.size()
	var gun := _weapons[_current]
	gun.visible = true
	_fire_cd = maxf(_fire_cd, SWAP_DELAY)
	_fire_cd_max = maxf(_fire_cd, 0.001)
	# Twirl + bounce the new gun in.
	gun.spin = TAU
	gun.position = weapon_hold + Vector2(0, 30)
	var tw := gun.create_tween().set_parallel(true)
	tw.tween_property(gun, "spin", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun, "position", weapon_hold, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sq = Vector2(1.12, 0.9)


## Kick the squash & stretch spring (used by weapons when they fire).
func squash(amount: Vector2) -> void:
	_sq = amount


func knock_back(impulse: Vector2) -> void:
	velocity += impulse
	_knock = KNOCK_TIME
	_coyote = 0.0
	if impulse.length() > 600.0:
		_dash_time = 0.0


## Called through the "player" group by every missile explosion.
func on_explosion(pos: Vector2, radius: float) -> void:
	var d := global_position - pos
	var dist := d.length()
	add_trauma(0.25 + 0.75 * clampf(1.0 - dist / (radius * 10.0), 0.0, 1.0))
	var reach := radius * 2.2
	if dist > reach:
		return
	var fall := 1.0 - dist / reach
	var dir := (d / maxf(dist, 0.001) + Vector2(0.0, -0.3)).normalized()
	knock_back(dir * BLAST_KNOCK * fall)
	_sq = Vector2(1.0 + 0.5 * fall, 1.0 - 0.4 * fall)


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	# Aim
	var to_mouse := get_global_mouse_position() - to_global(weapon_hold)
	if to_mouse.length() > 4.0:
		_aim = to_mouse.normalized()
	var flip_y := -1.0 if _aim.x < 0.0 else 1.0
	for gun in _weapons:
		gun.rotation = _aim.angle()
		gun.scale.y = flip_y
	var w := _weapon()
	if w:
		w.reload = 1.0 - _fire_cd / _fire_cd_max

	_reticle.paint_mode = _painting
	_reticle.has_target = not _pick.is_empty()
	_reticle.depth_scale = _pick.get("scale", 0.3)
	_reticle.ready_frac = 1.0 - _fire_cd / _fire_cd_max

	# Squash & stretch spring (underdamped so it jiggles), stretched by fall speed.
	var stretch := 0.0 if is_on_floor() else clampf(absf(velocity.y) / 2500.0, 0.0, 0.18)
	var target := Vector2(1.0 - stretch, 1.0 + stretch)
	_sq_vel += ((target - _sq) * SQ_K - _sq_vel * SQ_D) * delta
	_sq = (_sq + _sq_vel * delta).clamp(Vector2(0.4, 0.4), Vector2(1.8, 1.8))
	_sprite.scale = _sq
	_sprite.position.y = SPRITE_HALF * (1.0 - _sq.y)
	var lean := clampf(velocity.x / MAX_RUN, -1.5, 1.5) * 0.14
	_sprite.rotation = lerp_angle(_sprite.rotation, lean, 1.0 - exp(-20.0 * delta))
	_sprite.flip_h = _aim.x < 0.0

	# Screen shake
	if _cam:
		_trauma = maxf(_trauma - delta * 1.6, 0.0)
		var s := _trauma * _trauma
		_cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAX * s


func _spawn_ghost() -> void:
	var g := Sprite2D.new()
	g.texture = _sprite.texture
	g.flip_h = _sprite.flip_h
	g.material = FxLib.additive()
	g.modulate = Color(0.55, 0.8, 1.0, 0.6)
	g.z_index = z_index - 1
	get_parent().add_child(g)
	g.global_transform = _sprite.global_transform
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.28)
	tw.tween_callback(g.queue_free)
