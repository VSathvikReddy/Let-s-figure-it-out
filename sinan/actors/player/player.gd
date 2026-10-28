extends CharacterBody2D
## Celeste-style platformer controller with one weapon and a machete.
## Controls: A/D or arrows move, Space jump (again in the air = double jump),
## Shift dash, S/Down fast-fall (Down + Jump drops through hanging boards),
## mouse aims, LEFT click fires your weapon into the world, RIGHT click fires it
## into the painting (restores it), V / middle mouse = machete. The weapon comes
## from the Loadout in the skill tree.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")
const Reticle := preload("res://sinan/ui/aim/reticle.gd")
const AimGuide := preload("res://sinan/ui/aim/aim_guide.gd")
const Weapon := preload("res://sinan/weapons/weapon.gd")

## The equipped weapon and staff come from Progress (skill tree Loadout); these
## are only used if the skill tree data is missing.
@export var fallback_weapon: PackedScene = preload("res://sinan/weapons/pistol.tscn")
## Where the weapon is held, in player-local units.
@export var weapon_hold := Vector2(0, 10)  # start position only: guns follow the rig's hand
## Melee weapon on its own key (V / middle mouse), usable with any gun out.
@export var melee_weapon: PackedScene = preload("res://sinan/weapons/machete.tscn")
## Where the melee weapon is held, in player-local units.
@export var melee_hold := Vector2(-6, 6)
## The camera never shows anything outside this node's rectangle (a Control
## such as the frame's NinePatchRect, or a Sprite2D). Empty = no limits.
@export var camera_bounds: NodePath = ^"../frame/NinePatchRect"
## Pull the camera limits inwards (+) or let it see past the bounds (-), in px.
@export var camera_bounds_margin := 0.0

@export_group("Jumping")
## Extra jumps in mid-air (1 = double jump).
@export var air_jumps := 1
## Upward speed of an air jump (a little weaker than the ground jump).
@export var air_jump_velocity := -760.0
@export_group("")

@export_group("Aiming")
## The reticle (and the shot preview) can't go further than this from the player.
@export var aim_radius := 420.0
## Faint ring showing the aim limit when the cursor is pushed past it.
@export var show_aim_range := true
## Pull the (hidden) mouse pointer back onto the reticle when it goes past the
## aim radius, so there is no dead zone to drag back through.
@export var lock_cursor_to_aim_radius := true
## Dotted shot-trajectory preview. Off by default (the fixed aim radius is enough).
@export var show_trajectory := false

@export_group("Rig")
## Size of the character. The collision box is resized to match and the feet
## stay on the floor.
@export var body_scale := 2.2
## Angle (radians) the arm points at in the source image (it is drawn up-right).
@export var arm_image_angle := -0.8116
## Animation names in the AnimationPlayer.
@export var anim_idle := &"idle"
@export var anim_run := &"run"
@export var anim_jump := &"jump"
@export var anim_fall := &"fall"
@export var anim_dash := &"dash"
## Run animation speed at full run speed.
@export var run_anim_speed := 1.0
## Size of the held guns relative to their scenes (they were drawn for a bigger body).
@export var weapon_scale := 1.1
@export_group("")


@export_group("Screen Shake")
## Overall shake strength (0 = off, 1 = full).
@export_range(0.0, 2.0) var shake_strength := 0.7
## Largest camera offset at maximum shake (world px).
@export var max_shake_offset := 18.0
## Shake level never goes above this, however many things hit at once (0..1).
@export_range(0.0, 1.0) var max_trauma := 0.7
## Most shake that can be added in a single frame (stops many enemies stacking).
@export var trauma_per_frame_cap := 0.3
## How fast the shake dies down (per second).
@export var shake_decay := 2.4
## Rumble speed of the smooth noise shake.
@export var shake_frequency := 18.0
## Shakes coming from a position: full strength within this distance...
@export var shake_full_distance := 250.0
## ...fading to nothing at this distance.
@export var shake_zero_distance := 900.0

@export_group("Health")
@export var max_health := 5.0
## Seconds of invulnerability after taking a hit (0 = none: every hit counts).
## The skill tree's invulnerability upgrade adds to this.
@export var invulnerable_time := 0.0
## Protection right after respawning, so you are not hit the moment you appear.
@export var respawn_invulnerable := 1.0
## Default push when hurt (attacks can pass their own).
@export var hurt_knockback := 450.0
## Seconds between dying (smoke) and respawning at the start.
@export var respawn_delay := 0.9
## On death the camera zooms in on whatever killed the player.
@export var death_zoom := 1.8
## Seconds the death zoom takes to settle (and to ease back on respawn).
@export var death_zoom_time := 0.35

@export_group("Hurt Feedback")
## Screen shake when hit (0..1) - small and sharp.
@export_range(0.0, 1.0) var hurt_shake := 0.28
## Freeze frame when hit (real seconds; 0 = off) and how slow the game goes.
@export var hurt_freeze := 0.07
@export_range(0.0, 1.0) var hurt_freeze_scale := 0.04
## Blood droplets thrown from the body per hit (0 = none).
@export var blood_amount := 22
@export var blood_color := Color(0.62, 0.04, 0.06)
@export_group("")

signal health_changed(current: float, maximum: float)
signal died

var health := 5.0
var _invuln := 0.0
var _respawn_t := 0.0   # > 0 while dead (smoke, waiting to respawn)

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

# juice
const SQ_K := 320.0
const SQ_D := 14.0
const FEET_LOCAL_Y := 62.0  # feet height in player-local units, keeps them planted when squashing
const RIG_HEIGHT := 128.0   # unscaled rig height (head top to feet) used for the collision box
const RIG_WIDTH := 42.0
const FEET := Vector2(0, 18.6)
const RESPAWN_Y := 1400.0

var _coyote := 0.0
var _buffer := 0.0
var _knock := 0.0
var _dash_time := 0.0
var _dash_dir := 1.0
var _dashes := 1
var _air_jumps_left := 0
var _dash_cd := 0.0
var _ghost_t := 0.0
var _facing := 1.0
var _was_on_floor := false
var _fall_speed := 0.0
var _gun_cd := 0.0
var _gun_cd_max := 0.5
var _weapons: Array[Weapon] = []   # [gun, staff] (either may be missing)
var _gun: Weapon
var _loadout := Vector2i(-1, -1)   # equipped (weapon, staff) indices
var _base_max_health := 5.0
var _base_invuln := 0.0
var _hurt_flash := 0.0      # red flash after a hit (visual only)
var _regen_acc := 0.0
var _aim := Vector2.RIGHT
var _trauma := 0.0
var _trauma_this_frame := 0.0
var _shake_noise := FastNoiseLite.new()
var _shake_t := 0.0
var _sq := Vector2.ONE
var _sq_vel := Vector2.ZERO
var _spawn := Vector2.ZERO
var _painting := false     # right mouse held
var _pick := {}            # layer under the reticle (paint_picker.pick)

# Rig (palyer.tscn): Visual -> Body (body_scale) -> Rig -> BackArm, BackLeg, FrontLeg, Torso, Head,
# FrontArm/Hand. The AnimationPlayer animates the rig; this script flips the
# Visual, squashes it, aims FrontArm at the mouse and keeps the gun in the Hand.
@onready var _visual: Node2D = $Visual
@onready var _body: Node2D = $Visual/Body
@onready var _front_arm: Node2D = $Visual/Body/Rig/FrontArm
@onready var _hand: Node2D = $Visual/Body/Rig/FrontArm/Hand
@onready var _anim: AnimationPlayer = $AnimationPlayer
var _swap_drop := 0.0   # gun drops then bounces into the hand on weapon swap
var _cam: Camera2D
var _cam_zoom0 := Vector2.ONE
var _death_blend := 0.0       # 0 = normal camera, 1 = fully zoomed on the killer
var _death_source             # what killed us (an enemy), if it has a parent
var _death_pos := Vector2.ZERO  # where it hit from (hazards with no parent)
var _hit_source
var _hit_pos := Vector2.ZERO
var _guide: AimGuide
var _reticle: Reticle
var _melee  # the melee weapon instance (machete.gd)


func _ready() -> void:
	add_to_group("player")
	add_to_group("progress_listeners")
	_base_max_health = max_health
	_base_invuln = invulnerable_time
	_apply_upgrades()
	health = max_health
	_shake_noise.frequency = 0.08
	_apply_body_scale()
	_ensure_inputs()
	_spawn = global_position
	_cam = get_node_or_null("Camera2D")
	if _cam:
		_cam_zoom0 = _cam.zoom
	_apply_camera_limits.call_deferred()

	_equip_loadout()

	_guide = AimGuide.new()
	add_child(_guide)

	if melee_weapon:
		_melee = melee_weapon.instantiate()
		_melee.position = melee_hold
		_melee.z_index = 2
		add_child(_melee)
		_apply_weapon_upgrades()

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
	_add_action("fire_paint", [_mouse(MOUSE_BUTTON_RIGHT)])
	_add_action("melee", [_key(KEY_V), _mouse(MOUSE_BUTTON_MIDDLE)])


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
	if _respawn_t > 0.0:
		_respawn_t -= delta
		velocity = Vector2.ZERO
		if _respawn_t <= 0.0:
			_respawn()
		return
	var dir_x := Input.get_axis("move_left", "move_right")
	var on_floor := is_on_floor()

	_gun_cd = maxf(_gun_cd - delta, 0.0)
	_regenerate(delta)
	_knock = maxf(_knock - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_buffer = maxf(_buffer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_buffer = JUMP_BUFFER
	if on_floor:
		_coyote = COYOTE
		_air_jumps_left = air_jumps
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
		if _buffer > 0.0 and on_floor and Input.is_action_pressed("move_down") and NavGraph.drop_through(self):
			# Down + Jump on a hanging board: fall through it
			_buffer = 0.0
			_coyote = 0.0
		elif _buffer > 0.0 and _coyote > 0.0:
			_jump(dir_x)
		elif _buffer > 0.0 and _air_jumps_left > 0:
			_air_jump(dir_x)
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

	var mouse := aim_point()  # cursor clamped to the aim radius
	# what the cursor is over in the painting (right click fires there)
	_pick = PaintPicker.pick(get_parent(), mouse)

	if Input.is_action_just_pressed("melee") and _melee and _melee.swing(_aim):
		velocity.x += signf(_aim.x) * float(_melee.get("lunge_speed"))
		_sq = Vector2(1.15, 0.9)
		add_trauma(0.05)
	var w := _gun
	if w:
		# one weapon, two targets: left = the world, right = the painting.
		# Automatic weapons keep firing while either button is held.
		var world_shot := _wants_fire("fire", w)
		var paint_shot := not world_shot and _wants_fire("fire_paint", w) and not _pick.is_empty()
		_painting = paint_shot or (Input.is_action_pressed("fire_paint") and not _pick.is_empty())
		if (world_shot or paint_shot) and _gun_cd <= 0.0:
			_gun_cd = w.reload_time
			_gun_cd_max = maxf(w.reload_time, 0.001)
			w.fire(self, _aim, paint_shot, _pick, mouse)
			_reticle.fired()
		w.update_preview(_guide, _aim, get_rid(), _gun_cd <= 0.0)

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


## Double jump: a fresh kick upward with a puff of air under the feet.
func _air_jump(dir_x: float) -> void:
	_air_jumps_left -= 1
	velocity.y = air_jump_velocity
	if dir_x != 0.0 and signf(dir_x) != signf(velocity.x):
		velocity.x = dir_x * MAX_RUN * 0.6  # lets you change direction mid-air
	_buffer = 0.0
	_sq = Vector2(0.72, 1.32)
	var feet := global_position + FEET
	FxLib.burst(get_parent(), {
		"amount": 10, "life": 0.35, "v_min": 80.0, "v_max": 180.0, "direction": Vector2.DOWN, "spread": 70.0,
		"ramp": FxLib.gradient([[0.0, Color(1, 1, 1, 0.55)], [1.0, Color(1, 1, 1, 0.0)]]),
		"s_min": 0.12, "s_max": 0.25, "curve": FxLib.grow(), "damp_min": 200.0, "damp_max": 300.0,
	}, feet)


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

## The equipped weapon.
func _weapon() -> Weapon:
	return _gun


## Fire button pressed this frame, or held down for an automatic weapon.
func _wants_fire(action: StringName, w: Weapon) -> bool:
	return Input.is_action_just_pressed(action) or (w.automatic and Input.is_action_pressed(action))


## 0..1 reload progress for the UI.
func _cooldown_frac() -> float:
	return 1.0 - _gun_cd / _gun_cd_max


## Build the equipped weapon from Progress (skill tree Loadout).
func _equip_loadout() -> void:
	var t := Progress.tree()
	var wi := Progress.equipped_weapon()
	if Vector2i(wi, 0) == _loadout:
		return
	_loadout = Vector2i(wi, 0)
	for old in _weapons:
		old.queue_free()
	_weapons.clear()
	var gun_scene := fallback_weapon
	if t:
		if wi < t.weapon_scenes.size() and Progress.is_unlocked(t.weapon_unlock_stats[wi] if wi < t.weapon_unlock_stats.size() else &""):
			gun_scene = t.weapon_scenes[wi]
		elif not t.weapon_scenes.is_empty():
			gun_scene = t.weapon_scenes[0]
	_gun = _make_weapon(gun_scene)
	_apply_weapon_upgrades()


func _make_weapon(scene: PackedScene) -> Weapon:
	if scene == null:
		return null
	var w := scene.instantiate() as Weapon
	if w == null:
		push_warning("Loadout scene must use a script extending sinan/weapons/weapon.gd")
		return null
	w.position = weapon_hold
	w.z_index = 1
	# remember the scene values so upgrades always scale from them
	w.set_meta("base_damage", w.damage)
	w.set_meta("base_reload", w.reload_time)
	w.set_meta("base_radius", w.impact_radius)
	if "fuse_time" in w:
		w.set_meta("base_fuse", w.get("fuse_time"))
	add_child(w)
	_weapons.append(w)
	return w


## Apply skill-tree stats (called on start and after every purchase).
func _apply_upgrades() -> void:
	var old_max := max_health
	max_health = _base_max_health + Progress.stat(&"max_health")
	invulnerable_time = _base_invuln + Progress.stat(&"invuln_time")
	if is_inside_tree() and max_health != old_max:
		health = minf(health + (max_health - old_max), max_health)
		health_changed.emit(health, max_health)
	_apply_weapon_upgrades()


func _apply_weapon_upgrades() -> void:
	if _gun:
		# Weapons branch: damage + fire rate. Staff branch: painting radius,
		# cast rate and fuse - they apply to whatever is equipped.
		_gun.damage = float(_gun.get_meta("base_damage")) * (1.0 + Progress.stat(&"weapon_damage"))
		_gun.reload_time = float(_gun.get_meta("base_reload")) / (1.0 + Progress.stat(&"fire_rate") + Progress.stat(&"staff_rate"))
		_gun.impact_radius = float(_gun.get_meta("base_radius")) * (1.0 + Progress.stat(&"staff_radius"))
		if _gun.has_meta("base_fuse"):
			_gun.set("fuse_time", float(_gun.get_meta("base_fuse")) * maxf(0.2, 1.0 - Progress.stat(&"staff_fuse")))
	if _melee:
		if not _melee.has_meta("base_damage"):
			_melee.set_meta("base_damage", _melee.get("damage"))
		_melee.set("damage", float(_melee.get_meta("base_damage")) * (1.0 + Progress.stat(&"machete_damage")))


## Called through the "progress_listeners" group (coins, purchases, loadout).
func on_progress_changed() -> void:
	_apply_upgrades()
	_equip_loadout()


func _regenerate(delta: float) -> void:
	var regen := Progress.stat(&"health_regen")
	if regen <= 0.0 or health >= max_health or not is_alive():
		return
	health = minf(health + regen * delta, max_health)
	_regen_acc += regen * delta
	if _regen_acc >= 0.05:
		_regen_acc = 0.0
		health_changed.emit(health, max_health)


# ---------------------------------------------------------------- coins

## Collected coins (from the PickupField). Returns how many were taken.
func add_coins(amount: int) -> int:
	return Progress.add_coins(amount, self)


## Grow the rig around the feet and fit the collision box to it.
func _apply_body_scale() -> void:
	_body.scale = Vector2.ONE * body_scale
	_body.position.y = FEET_LOCAL_Y * (1.0 - body_scale)
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col and col.shape is RectangleShape2D:
		var shape := (col.shape as RectangleShape2D).duplicate() as RectangleShape2D
		var height := RIG_HEIGHT * body_scale
		shape.size = Vector2(RIG_WIDTH * body_scale, height)
		col.shape = shape
		col.position = Vector2(0.0, FEET_LOCAL_Y - height * 0.5)


## The front arm's shoulder: centre of the aim radius.
func _shoulder() -> Vector2:
	return _front_arm.global_position


## Where the player is aiming: the cursor, clamped to the aim radius around
## the weapon hand (one radius for world and painting shots).
func aim_point() -> Vector2:
	var center := _shoulder()
	return center + (get_global_mouse_position() - center).limit_length(aim_radius)


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
	add_trauma(0.45, pos)
	var reach := radius * 2.2
	if dist > reach:
		return
	var fall := 1.0 - dist / reach
	var dir := (d / maxf(dist, 0.001) + Vector2(0.0, -0.3)).normalized()
	knock_back(dir * BLAST_KNOCK * fall)
	_sq = Vector2(1.0 + 0.5 * fall, 1.0 - 0.4 * fall)


## Called by enemy attacks. knockback < 0 uses hurt_knockback.
## Called by enemy attacks. knockback < 0 uses hurt_knockback, 0 = no push.
## ignore_invulnerability: for constant attacks like clinging goblin claws.
## source: the enemy that dealt it (orbs pass whoever fired them); leave out for a
## hazard with no owner - the death camera then looks at from_pos instead.
func take_damage(amount: float, from_pos: Vector2, knockback := -1.0, ignore_invulnerability := false, source = null) -> void:
	if health <= 0.0 or _respawn_t > 0.0:
		return
	if _invuln > 0.0 and not ignore_invulnerability:
		return
	_hit_source = source if is_instance_valid(source) else null
	_hit_pos = from_pos
	health -= amount * (1.0 - clampf(Progress.stat(&"damage_reduction"), 0.0, 0.8))
	_invuln = maxf(_invuln, invulnerable_time)
	_hurt_flash = 0.18
	health_changed.emit(health, max_health)
	var push := hurt_knockback if knockback < 0.0 else knockback
	var dir := (global_position - from_pos).normalized()
	if push > 0.0:
		knock_back(Vector2(signf(dir.x) if dir.x != 0.0 else -_facing, -0.5).normalized() * push)
	_sq = Vector2(1.3, 0.75)
	_hurt_feedback(dir, amount)
	if health <= 0.0:
		_die()


## Being hit: a small sharp shake, a freeze frame, and blood thrown from the
## body away from the hit (spray + heavier drops that fall).
## Small hits (a bat nip) get a lighter version: less shake and blood, no freeze.
func _hurt_feedback(away: Vector2, amount := 1.0) -> void:
	var w := clampf(amount / 0.75, 0.25, 1.0)
	add_trauma(hurt_shake * w)
	if amount >= 0.3:
		FxLib.hit_stop(get_tree(), hurt_freeze, hurt_freeze_scale)
	var drops := int(blood_amount * w)
	if drops <= 0:
		return
	if away == Vector2.ZERO:
		away = Vector2(-_facing, 0.0)
	var world := get_parent()
	var chest := global_position + Vector2(0, -28)
	var deep := blood_color.darkened(0.45)
	# fine spray in a cone away from the hit
	FxLib.burst(world, {
		"amount": drops, "life": 0.45, "life_rand": 0.4, "v_min": 160.0, "v_max": 420.0,
		"direction": Vector2(signf(away.x) if away.x != 0.0 else 1.0, -0.6), "spread": 38.0,
		"gravity": Vector2(0, 1400), "damp_min": 40.0, "damp_max": 120.0,
		"s_min": 0.035, "s_max": 0.08, "curve": FxLib.shrink(), "emit_radius": 6.0,
		"texture": FxLib.glow(), "angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"ramp": FxLib.gradient([[0.0, Color(blood_color.lightened(0.15), 1.0)], [0.6, Color(blood_color, 0.95)], [1.0, Color(deep, 0.0)]]),
	}, chest)
	# a few bigger drops that arc and fall
	FxLib.burst(world, {
		"amount": maxi(drops / 4, 2), "life": 0.7, "v_min": 90.0, "v_max": 220.0,
		"direction": Vector2(signf(away.x) if away.x != 0.0 else 1.0, -1.0), "spread": 50.0,
		"gravity": Vector2(0, 1600), "s_min": 0.07, "s_max": 0.12, "curve": FxLib.shrink(),
		"texture": FxLib.glow(), "spin_min": 0.0, "spin_max": 0.0,
		"ramp": FxLib.gradient([[0.0, Color(blood_color, 1.0)], [1.0, Color(deep, 0.0)]]),
	}, chest)


func _die() -> void:
	died.emit()
	_death_source = _hit_source
	_death_pos = _hit_pos
	# Vanish in a burst of smoke, then respawn at the start (no game-over screen yet).
	var world := get_parent()
	FxLib.smoke_burst(world, global_position, 1.2, Color(0.28, 0.24, 0.26), 20)
	FxLib.burst(world, {
		"amount": 18, "life": 0.5, "v_min": 120.0, "v_max": 320.0, "texture": FxLib.glow(),
		"s_min": 0.05, "s_max": 0.1, "damp_min": 150.0, "damp_max": 300.0,
		"ramp": FxLib.fade_ramp(Color(1.0, 0.3, 0.3)), "additive": true, "curve": null,
	}, global_position)
	FxLib.flash_light(world, global_position, Color(1.0, 0.4, 0.35), 2.0, 2.0, 0.4)
	add_trauma(0.6)
	visible = false
	velocity = Vector2.ZERO
	_respawn_t = maxf(respawn_delay, 0.01)


func _respawn() -> void:
	global_position = _spawn
	velocity = Vector2.ZERO
	health = max_health
	_invuln = maxf(invulnerable_time, respawn_invulnerable)
	visible = true
	health_changed.emit(health, max_health)
	FxLib.smoke_burst(get_parent(), global_position, 0.7, Color(0.85, 0.85, 0.9), 10)


## False while dead / waiting to respawn.
func is_alive() -> bool:
	return _respawn_t <= 0.0 and health > 0.0


## Add screen shake. Pass `from` (global position of the cause) so far-away
## events shake less; shakes from the player's own actions leave it out.
func add_trauma(amount: float, from := Vector2.INF) -> void:
	if from != Vector2.INF:
		var d := global_position.distance_to(from)
		amount *= 1.0 - clampf((d - shake_full_distance) / maxf(shake_zero_distance - shake_full_distance, 1.0), 0.0, 1.0)
	amount *= shake_strength
	# per-frame budget: a crowd hitting at once counts as one big hit, not ten
	amount = minf(amount, maxf(trauma_per_frame_cap - _trauma_this_frame, 0.0))
	if amount <= 0.0:
		return
	_trauma_this_frame += amount
	_trauma = minf(_trauma + amount, max_trauma)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	# Aim
	var to_mouse := get_global_mouse_position() - _shoulder()
	if to_mouse.length() > 4.0:
		_aim = to_mouse.normalized()
	var flip_y := -1.0 if _aim.x < 0.0 else 1.0
	# Front arm points at the aim. The Visual is mirrored when facing left, and a
	# mirrored parent turns angle a into PI - a, so undo that here.
	var aim_local := _aim.angle() if flip_y > 0.0 else PI - _aim.angle()
	_front_arm.rotation = aim_local - arm_image_angle
	var hand := to_local(_hand.global_position) + Vector2(0.0, _swap_drop)
	for gun in _weapons:
		gun.rotation = _aim.angle()
		gun.scale = Vector2(weapon_scale, weapon_scale * flip_y)
		gun.position = hand
	var w := _weapon()
	if w:
		w.reload = _cooldown_frac()

	var center := _shoulder()
	var limit := aim_radius
	_reticle.aim_point = aim_point()
	_guide.range_center = center
	_guide.range_radius = limit
	# fade the range ring in as the cursor pushes past the limit
	var over := (get_global_mouse_position() - center).length() - limit
	_guide.range_visibility = clampf(over / 60.0, 0.0, 1.0) if show_aim_range else 0.0
	if lock_cursor_to_aim_radius and over > 0.0:
		# move the real pointer back onto the clamped aim point (viewport coordinates)
		get_viewport().warp_mouse(get_viewport().get_canvas_transform() * aim_point())
		_guide.range_visibility = 1.0 if show_aim_range else 0.0
	_guide.show_path = show_trajectory
	_reticle.paint_mode = Input.is_action_pressed("fire_paint") and not _pick.is_empty()
	_reticle.has_target = not _pick.is_empty()
	_reticle.depth_scale = _pick.get("scale", 0.3)
	_reticle.ready_frac = _cooldown_frac()

	# Squash & stretch spring (underdamped so it jiggles), stretched by fall speed.
	var stretch := 0.0 if is_on_floor() else clampf(absf(velocity.y) / 2500.0, 0.0, 0.18)
	var target := Vector2(1.0 - stretch, 1.0 + stretch)
	_sq_vel += ((target - _sq) * SQ_K - _sq_vel * SQ_D) * delta
	_sq = (_sq + _sq_vel * delta).clamp(Vector2(0.4, 0.4), Vector2(1.8, 1.8))
	# face the aim; squash around the feet
	_visual.scale = Vector2(_sq.x * flip_y, _sq.y)
	_visual.position.y = FEET_LOCAL_Y * (1.0 - _sq.y)
	var lean := clampf(velocity.x / MAX_RUN, -1.5, 1.5) * 0.1
	_visual.rotation = lerp_angle(_visual.rotation, lean, 1.0 - exp(-20.0 * delta))
	_update_animation()

	# Hurt: red flash, then blink while invulnerable
	_invuln = maxf(_invuln - delta, 0.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	var red := clampf(_hurt_flash / 0.18, 0.0, 1.0)
	if _invuln > 0.0:
		# blink while protected (respawn, or the skill-tree upgrade)
		_visual.modulate = Color(1.0, 1.0 - red * 0.7, 1.0 - red * 0.7, 0.35 if int(_invuln * 16.0) % 2 == 0 else 1.0)
	elif red > 0.0:
		_visual.modulate = Color(1.0, 1.0 - red * 0.7, 1.0 - red * 0.7, 1.0)
	else:
		_visual.modulate = Color.WHITE

	# Screen shake
	if _cam:
		_trauma_this_frame = 0.0
		_trauma = maxf(_trauma - delta * shake_decay, 0.0)
		_shake_t += delta * shake_frequency
		var s := _trauma  # linear: small hits stay visible, the cap keeps crowds in check
		# smooth noise rumble instead of a random jump every frame
		var shake := Vector2(_shake_noise.get_noise_2d(_shake_t, 0.0), _shake_noise.get_noise_2d(0.0, _shake_t)) * 2.0 * max_shake_offset * s
		_update_death_cam(delta)
		_cam.offset = shake + _death_offset()


## Death camera: while dead, ease in on the thing that killed us; ease back out
## after respawning.
func _update_death_cam(delta: float) -> void:
	var step := delta / maxf(death_zoom_time, 0.01)
	_death_blend = clampf(_death_blend + (step if _respawn_t > 0.0 else -step), 0.0, 1.0)
	var k := smoothstep(0.0, 1.0, _death_blend)
	_cam.zoom = _cam_zoom0.lerp(_cam_zoom0 * death_zoom, k)


## Camera offset towards the killer (its live position if it is still around).
func _death_offset() -> Vector2:
	if _death_blend <= 0.0:
		return Vector2.ZERO
	var at := _death_pos
	if is_instance_valid(_death_source):
		at = (_death_source as Node2D).global_position
	# measured from the camera's own resting spot (it sits well above the
	# player), so the killer ends up in the middle of the view, not just level with it
	return (at - _cam.global_position) * smoothstep(0.0, 1.0, _death_blend)


## Pick the rig animation from the movement state.
func _update_animation() -> void:
	var wanted := anim_idle
	var speed := 1.0
	if _dash_time > 0.0:
		wanted = anim_dash
	elif not is_on_floor():
		wanted = anim_jump if velocity.y < 0.0 else anim_fall
	elif absf(velocity.x) > 40.0:
		wanted = anim_run
		speed = run_anim_speed * clampf(absf(velocity.x) / MAX_RUN, 0.5, 1.6)
	_anim.speed_scale = speed
	if _anim.current_animation != wanted and _anim.has_animation(wanted):
		_anim.play(wanted, 0.08)


## Dash afterimage: a tinted copy of the whole rig that fades out.
func _spawn_ghost() -> void:
	var g := _visual.duplicate() as Node2D
	g.modulate = Color(0.55, 0.8, 1.0, 0.55)
	g.z_index = z_index - 1
	get_parent().add_child(g)
	g.global_transform = _visual.global_transform
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.28)
	tw.tween_callback(g.queue_free)
