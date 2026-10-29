extends CharacterBody2D
## Witch enemy (Clash of Clans-style). Drag witch.tscn into a level; she finds
## the player through the "player" group.
##
## Abilities
##  - Homing Orbs (Radiance-style): raises her staff and conjures orbs one by
##    one; each charges, then slowly chases the player with limited steering, so
##    a well-timed dash or jump dodges it. They detonate after a few seconds.
##  - Staff Melee: close-range swing with a purple swoosh and knockback.
##  - Summon Ghosts: channels a rune circle; when it completes, ghosts rise and
##    attack the painting. Getting hit while channelling cancels it.
##  - Teleport: a pressure meter fills while the player is close, shares her
##    board, or keeps landing shots on her. Past the threshold (or right after
##    a volley / summon) she flares a rune for a moment (the tell - she can be
##    punished), collapses into ink and reappears on a different board at
##    casting distance. A single shot never makes her teleport.
##
## Visuals are nodes in witch.tscn, cut from sinan/assets/sprites/witch.png
## (Sprite2D + Region, so repainting the sheet updates her):
##   Visual            - flipped to face the player (do not animate it)
##   Visual/Rig        - animated by the AnimationPlayer (idle, walk, cast, summon, hurt)
##   Rig/Cape, Rig/BackArm, Rig/BackLeg, Rig/FrontLeg - animated limb pivots
##   Rig/Body, Rig/Head                       - torso and hood
##   Rig/StaffPivot    - rotated by this script to raise / aim; holds FrontArm + Staff
##   StaffPivot/Staff/Tip    - Marker2D: where orbs and sparks come from (the flame)
##   StaffPivot/Staff/OrbGlow - glow on the flame that brightens while casting
##   SummonCircle      - rune circle node (summon_circle.gd), shown while summoning
##   Shadow            - Sprite2D ground shadow
##
## AI: keeps her preferred distance, never walks off ledges, summons only when it
## is safe (player far away or busy aiming into the painting), backs away when
## the player closes in while still casting orbs, and blinks out when rushed.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const OrbBlast := preload("res://sinan/fx/blasts/orb_blast.gd")
const HexBlast := preload("res://sinan/fx/blasts/hex_blast.gd")
const PaintStroke := preload("res://sinan/fx/marks/paint_stroke.gd")
const WitchOrb := preload("res://sinan/actors/enemies/witch/witch_orb.gd")

enum State { MOVE, MELEE_WINDUP, MELEE_RECOVER, ORB_WINDUP, ORB_CASTING, SUMMONING, TELEPORT_TELL, HURT, DEAD }

signal died

@export_group("Health")
@export var max_health := 30.0
## Hits doing at least this much damage make her stagger (summoning is always cancelled).
@export var stagger_damage := 3.0
@export var stagger_time := 0.35
@export var hurt_knockback := 160.0

@export_group("Movement")
@export var walk_speed := 90.0
@export var gravity := 1600.0
## She tries to stay between these distances from the player.
@export var preferred_distance_min := 220.0
@export var preferred_distance_max := 380.0
## How far ahead she checks for a ledge before walking.
@export var ledge_check_distance := 30.0
## Back away when the player comes closer than preferred_distance_min.
@export var retreat_when_close := true
@export var retreat_speed := 130.0
## Keep walking (retreating/strafing) while conjuring orbs instead of standing still.
@export var cast_orbs_while_moving := true

@export_group("Senses")
## She ignores the player beyond this distance.
@export var detection_range := 1000.0
## Seconds between decisions (lower = reacts faster).
@export var think_interval := 0.2
## Only cast orbs when nothing solid is between her and the player.
@export var orbs_need_line_of_sight := false

@export_group("Staff Melee")
## Off by default: she prefers to retreat and keep casting orbs.
@export var use_staff_melee := false
@export var melee_range := 60.0
@export var melee_damage := 1.0
@export var melee_windup := 0.35
@export var melee_cooldown := 1.6
@export var melee_knockback := 520.0

@export_group("Homing Orbs")
## She only casts orbs when the player is within this distance.
@export var orb_attack_range := 650.0
@export var orb_damage := 1.0
## Staff-raise before the first orb appears.
@export var orb_cast_windup := 0.45
@export var orb_attack_cooldown := 3.2
@export var orbs_per_cast := 3
## Seconds between each orb appearing.
@export var orb_spawn_interval := 0.3
## How far around her staff the orbs appear.
@export var orb_spawn_spread := 45.0
## Each orb swells and glows this long before it starts chasing.
@export var orb_charge_time := 0.6
## Top speed of an orb (keep it below the player's run speed so it can be outrun).
@export var orb_max_speed := 230.0
## How sharply an orb can change direction (lower = wider turns, easier to dodge).
@export var orb_steering := 260.0
## Seconds an orb chases before it detonates.
@export var orb_lifetime := 4.5
## When an orb times out it explodes: damage radius and damage.
@export var orb_end_explosion_radius := 45.0
@export var orb_end_explosion_damage := 1.0
@export var orbs_pass_through_walls := false
@export var orb_size := 9.0
## She waits if this many of her orbs are already flying.
@export var max_orbs_alive := 6

@export_group("Teleport")
@export var blink_enabled := true
## Pressure (0..1+) needed to teleport.
@export var pressure_threshold := 1.0
## Pressure per second while the player is closer than this.
@export var pressure_close_distance := 200.0
@export var pressure_close_rate := 0.7
## Pressure per second while the player stands on her board / floor.
@export var pressure_same_surface_rate := 0.25
## Pressure per hit taken (one hit alone stays below the threshold).
@export var pressure_per_hit := 0.3
## Pressure lost per second.
@export var pressure_decay := 0.35
## Chance to teleport right after a volley or summon (if the cooldown allows).
@export_range(0.0, 1.0) var teleport_after_cast_chance := 0.35
## Rune flare before she vanishes - the player's window to punish her.
@export var teleport_tell := 0.4
@export var blink_cooldown := 3.0
## Used when there are no boards to teleport to.
@export var blink_distance := 280.0
## She avoids the boards she used most recently (how many to remember).
@export var teleport_memory := 2

@export_group("Summon Ghosts")
@export var ghost_scene: PackedScene
## Seconds she must channel uninterrupted. Any hit cancels and resets it.
@export var summon_time := 1.4
@export var summon_cooldown := 7.0
## Cooldown after her summon is interrupted (shorter, she will try again).
@export var interrupted_summon_cooldown := 2.5
@export var ghosts_per_summon := 2
@export var max_ghosts_alive := 4
## She only starts summoning if the player is at least this far away...
@export var safe_summon_distance := 300.0
## ...or the player is busy aiming into the painting.
@export var summon_while_player_aims_at_painting := true

@export_group("Ghost")
## How high ghosts float up out of the circle, and how slowly (seconds).
@export var ghost_rise_height := 140.0
@export var ghost_rise_time := 2.4
## Seconds a ghost takes to glide from the top of its rise into the painting.
@export var ghost_glide_time := 1.8
@export var ghost_haunt_time := 2.0
@export var ghost_distortion_radius := 110.0
@export var ghost_distortion_strength := 1.0
## Ghosts pick the least distorted spot they can find (undo the player's work).
@export var ghosts_target_restored_areas := true
@export var ghost_color := Color(1.0, 0.82, 0.86)

@export_group("Drops")
## Which drop table in game_data.tres this enemy uses when it dies.
@export var drop_table := &"witch"
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

@export_group("Effect Colours")
## Orbs, sparks, staff glow, summon circle.
@export var magic_color := Color(1.0, 0.36, 0.42)
@export var eye_glow_color := Color(1.0, 0.8, 0.82)
## Blink and death smoke.
@export var smoke_color := Color(0.16, 0.14, 0.16)
## Staff light brightness (it grows while casting / summoning).
@export var staff_light_energy := 0.4
## How much the orb glow swells while casting (0 = not at all).
@export var orb_glow_growth := 0.6

@export_group("Animation Names")
@export var anim_idle := &"idle"
@export var anim_walk := &"walk"
@export var anim_cast := &"cast"
@export var anim_summon := &"summon"
@export var anim_hurt := &"hurt"

var health := 30.0

var _state := State.MOVE
var _state_t := 0.0
var _t := 0.0
var _think_t := 0.0
var _move_dir := 0.0
var _face := 1.0
var _player  # the player node (found through the "player" group)

var _melee_cd := 0.0
var _orb_cd := 0.0
var _blink_cd := 0.0
var _pressure := 0.0
var _recent_surfaces: Array[int] = []
var _ghost_actions := 0      # actions taken while her ghosts are out (max 1)
var _vis_scale := Vector2.ONE
var _tp_scale := Vector2.ONE # squash used by the teleport collapse / burst
var _tp_tw: Tween            # the teleport tell squash
var _ground_cache := {}      # ledge checks: 8 px spot -> floor ahead
var _ground_cache_t := 0.0
var _think_dt := 0.0         # time since her AI last ran (less often far off screen)
var _nav: NavGraph
var _feet := 35.0          # bottom of the collision shape (from the scene)
var _summon_cd := 3.0       # first summon a few seconds in
var _since_hurt := 99.0
var _orbs_left := 0
var _orb_spawn_t := 0.0
var _orbs: Array[Node] = []
var _ghosts: Array[Node] = []

var _charge := 0.0          # staff orb glow while casting
var _staff_angle := -0.15   # radians from vertical, + leans forward
var _appear := 1.0          # fade-in after a blink
var _dissolve := 0.0        # death fade

var _summon_fx: CPUParticles2D
var _light: PointLight2D


@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var staff_pivot: Node2D = $Visual/Rig/StaffPivot
@onready var staff_tip: Node2D = $Visual/Rig/StaffPivot/Staff/Tip
@onready var orb_glow: CanvasItem = $Visual/Rig/StaffPivot/Staff/OrbGlow
@onready var summon_circle: Node2D = $SummonCircle
var _orb_glow_scale := Vector2.ONE


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	z_index = 2
	set_meta("mass", 0.9)
	_vis_scale = visual.scale.abs()
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape is CapsuleShape2D:
		_feet = cs.position.y + (cs.shape as CapsuleShape2D).height * 0.5
	# the glow around her (the Light node in witch.tscn; tune it there)
	_light = get_node_or_null("Light") as PointLight2D
	if _light == null:
		_light = PointLight2D.new()
		_light.texture = FxLib.glow()
		_light.texture_scale = 1.5
		add_child(_light)
	_light.color = magic_color
	_light.energy = staff_light_energy
	_summon_fx = FxLib.emitter({
		"one_shot": false, "amount": 30, "life": 0.9, "v_min": 30.0, "v_max": 70.0,
		"direction": Vector2.UP, "spread": 15.0, "emit_radius": 34.0, "gravity": Vector2(0, -60),
		"texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.12,
		"ramp": FxLib.fade_ramp(magic_color), "additive": true, "curve": null,
	})
	_summon_fx.local_coords = true
	_summon_fx.position = Vector2(0, _feet)
	_summon_fx.emitting = false
	add_child(_summon_fx)
	_orb_glow_scale = (orb_glow as Node2D).scale if orb_glow is Node2D else Vector2.ONE
	summon_circle.visible = false
	if summon_circle.get("color") != null:
		summon_circle.set("color", magic_color)
		summon_circle.set("rune_color", magic_color.lerp(Color(1.0, 0.85, 0.6), 0.5))


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	# far off screen the AI runs every few frames; she still falls and moves every frame
	var step := delta
	_think_dt += delta
	if not View.think(self):
		if not is_on_floor():
			velocity.y = minf(velocity.y + gravity * step, 1400.0)
		move_and_slide()
		return
	delta = _think_dt  # timers catch up on the frames she skipped
	_think_dt = 0.0
	_t += delta
	_state_t += delta
	_melee_cd -= delta
	_orb_cd -= delta
	_blink_cd -= delta
	_summon_cd -= delta
	_since_hurt += delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_nav):
		_nav = get_tree().get_first_node_in_group("nav_graph")
	_update_pressure(delta)
	if _ghosts_alive() == 0:
		_ghost_actions = 0

	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * step, 1400.0)

	match _state:
		State.MOVE:
			_think_t -= delta
			if _think_t <= 0.0:
				_think_t = think_interval * randf_range(0.8, 1.2)
				_decide()
			if _state == State.MOVE:
				_walk(delta)
				_staff_angle = lerp_angle(_staff_angle, -0.15, 8.0 * delta)
		State.MELEE_WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
			_staff_angle = lerp_angle(_staff_angle, -1.3, 14.0 * delta)
			if _state_t >= melee_windup:
				_do_melee()
		State.MELEE_RECOVER:
			_staff_angle = lerp_angle(_staff_angle, 1.5, 25.0 * delta)
			if _state_t >= 0.35:
				_set_state(State.MOVE)
		State.ORB_WINDUP:
			_walk_while_casting(delta)
			_face_player()
			_charge = clampf(_state_t / orb_cast_windup, 0.0, 1.0)
			_staff_angle = lerp_angle(_staff_angle, -0.35, 10.0 * delta)  # staff raised high
			if _state_t >= orb_cast_windup:
				_orbs_left = maxi(orbs_per_cast, 1)
				_orb_spawn_t = 0.0
				_orb_cd = orb_attack_cooldown * randf_range(0.85, 1.15)
				_set_state(State.ORB_CASTING)
		State.ORB_CASTING:
			_walk_while_casting(delta)
			_face_player()
			_charge = 1.0
			_staff_angle = lerp_angle(_staff_angle, -0.35 + sin(_t * 8.0) * 0.12, 10.0 * delta)
			_orb_spawn_t -= delta
			if _orbs_left > 0 and _orb_spawn_t <= 0.0:
				_spawn_orb(orbs_per_cast - _orbs_left)
				_orbs_left -= 1
				_orb_spawn_t = orb_spawn_interval
			if _orbs_left <= 0 and _orb_spawn_t <= 0.0:
				_set_state(State.MOVE)
				_maybe_teleport_after_cast()
		State.SUMMONING:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
			_staff_angle = lerp_angle(_staff_angle, 0.0, 8.0 * delta)
			_charge = clampf(_state_t / summon_time, 0.0, 1.0)
			if _state_t >= summon_time:
				_finish_summon()
		State.TELEPORT_TELL:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			_staff_angle = lerp_angle(_staff_angle, -0.6, 12.0 * delta)
			_charge = clampf(_state_t / teleport_tell, 0.0, 1.0)
			if _state_t >= teleport_tell:
				_teleport()
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
			if _state_t >= stagger_time:
				_set_state(State.MOVE)

	move_and_slide()


func _set_state(s: State) -> void:
	if _state == State.TELEPORT_TELL and s != State.TELEPORT_TELL and _tp_tw:
		_tp_tw.kill()  # interrupted (or done): the squash springs back in _process
	_state = s
	_state_t = 0.0
	if s == State.MOVE:
		_charge = 0.0


# ---------------------------------------------------------------- decisions

func _decide() -> void:
	if not is_instance_valid(_player) or not _player.is_alive():
		_move_dir = 0.0
		return
	var to: Vector2 = _player.global_position - global_position
	var dist := to.length()
	_face_player()
	if dist > detection_range:
		_move_dir = 0.0
		return

	# Positioning first, so abilities can be used on the move.
	_choose_move_dir(dist)

	# 1. Optional staff swing if the player is right on top of her.
	if use_staff_melee and dist <= melee_range and _melee_cd <= 0.0:
		_set_state(State.MELEE_WINDUP)
		_spark_burst(_staff_tip(), 6, magic_color)
		return
	# 2. Under pressure: telegraph, then teleport to another board.
	if blink_enabled and _pressure >= pressure_threshold and _blink_cd <= 0.0 and _may_act():
		_start_teleport()
		return
	# 3. Summon only when it is safe: player far away, or busy aiming at the painting,
	#    and she has not just been hit (she would get interrupted).
	if ghost_scene and _summon_cd <= 0.0 and _ghosts_alive() < max_ghosts_alive and _since_hurt > 1.0:
		var player_busy: bool = summon_while_player_aims_at_painting and _player.get("_painting") == true
		if dist >= safe_summon_distance or player_busy:
			_start_summon()
			return
	# 4. Orbs when in range and the sky is not already full of them (also while retreating).
	if _orb_cd <= 0.0 and dist <= orb_attack_range and _orbs_alive() < max_orbs_alive 			and (not orbs_need_line_of_sight or _can_see_player()) and _may_act():
		_set_state(State.ORB_WINDUP)
		_converge_fx()
		if _ghosts_alive() > 0:
			_ghost_actions += 1


## Keep the preferred distance: retreat when the player is close, approach when
## far, small strafes in between. Never walks off a ledge.
func _choose_move_dir(dist: float) -> void:
	if dist < preferred_distance_min:
		_move_dir = -_face if retreat_when_close else 0.0
	elif dist > preferred_distance_max:
		_move_dir = _face
	else:
		_move_dir = [-0.5, 0.0, 0.0, 0.5].pick_random()
	if _move_dir != 0.0 and not _ground_ahead(signf(_move_dir)):
		_move_dir = 0.0
		# cornered at a ledge while the player closes in: pressure builds fast
		if dist < preferred_distance_min:
			_pressure += 0.15


func _is_retreating() -> bool:
	return _move_dir != 0.0 and signf(_move_dir) == -_face


func _walk(delta: float) -> void:
	if _move_dir != 0.0 and not _ground_ahead(signf(_move_dir)):
		_move_dir = 0.0
	var speed := retreat_speed if _is_retreating() else walk_speed
	velocity.x = move_toward(velocity.x, _move_dir * speed, 900.0 * delta)


func _walk_while_casting(delta: float) -> void:
	if cast_orbs_while_moving:
		_walk(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)


func _face_player() -> void:
	if is_instance_valid(_player):
		var dx: float = _player.global_position.x - global_position.x
		if absf(dx) > 2.0:
			_face = signf(dx)


func _can_see_player() -> bool:
	# The player's own body is on the world layer too, so ignore it.
	var ex: Array[RID] = [get_rid()]
	if _player is CollisionObject2D:
		ex.append(_player.get_rid())
	var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -10), _player.global_position, 1, ex)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _ground_ahead(dir: float) -> bool:
	# short ray: the floor far below a board does not count as ground ahead.
	# Cached for a moment per 8 px spot (asked every frame while walking).
	var x := global_position.x + dir * ledge_check_distance
	var key := Vector2i(floori(x / 8.0), floori(global_position.y / 4.0))
	if _t - _ground_cache_t > 0.15:
		_ground_cache_t = _t
		_ground_cache.clear()
	if not _ground_cache.has(key):
		_ground_cache[key] = _ground_at(x, _feet + 50.0) != null
	return _ground_cache[key]


## Floor point under x (searching `depth` px down), or null.
func _ground_at(x: float, depth := 300.0) -> Variant:
	var from := Vector2(x, global_position.y - 40.0)
	var ex: Array[RID] = [get_rid()]
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, depth + 40.0), 1, ex)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return null if hit.is_empty() else hit.position


func _ghosts_alive() -> int:
	for i in range(_ghosts.size() - 1, -1, -1):
		if not is_instance_valid(_ghosts[i]):
			_ghosts.remove_at(i)
	return _ghosts.size()


func _staff_tip() -> Vector2:
	return staff_tip.global_position


# ---------------------------------------------------------------- abilities

func _do_melee() -> void:
	_melee_cd = melee_cooldown
	_set_state(State.MELEE_RECOVER)
	var world := get_parent()
	var s := PaintStroke.new()
	s.radius = 34.0
	s.sweep = 2.4
	s.width = 9.0
	s.color = magic_color
	s.shade = smoke_color
	s.life = 0.3
	s.position = FxLib.to_parent_space(world, global_position + Vector2(0, -4))
	s.rotation = 0.0 if _face > 0.0 else PI
	world.add_child(s)
	_spark_burst(global_position + Vector2(_face * 30.0, -4), 10, magic_color)
	if is_instance_valid(_player):
		var d: Vector2 = _player.global_position - global_position
		if d.length() <= melee_range * 1.3 and signf(d.x) == _face and _player.has_method("take_damage"):
			_player.take_damage(melee_damage, global_position, melee_knockback, false, self)


## Conjure one orb on a fan above/around the staff tip (index = order in the cast).
func _spawn_orb(index: int) -> void:
	if not is_instance_valid(_player):
		return
	var n := maxi(orbs_per_cast, 1)
	var spread := 0.0 if n == 1 else (float(index) / (n - 1) - 0.5) * 2.0  # -1 .. 1
	var ang := -PI / 2.0 + spread * 1.1 + randf_range(-0.15, 0.15)
	var at := _staff_tip() + Vector2.from_angle(ang) * orb_spawn_spread
	var o := WitchOrb.new()
	o.shooter = self
	o.charge_time = orb_charge_time
	o.max_speed = orb_max_speed
	o.steering = orb_steering
	o.lifetime = orb_lifetime
	o.end_explosion_radius = orb_end_explosion_radius
	o.end_explosion_damage = orb_end_explosion_damage
	o.damage = orb_damage
	o.pass_through_walls = orbs_pass_through_walls
	o.orb_radius = orb_size
	o.orb_color = magic_color
	o.core_color = eye_glow_color
	o.target = _player
	o.shooter_rid = get_rid()
	var world := get_parent()
	o.position = FxLib.to_parent_space(world, at)
	world.add_child(o)
	_orbs.append(o)
	FxLib.flash_light(world, at, magic_color, 1.5, 1.2, 0.2)


func _orbs_alive() -> int:
	for i in range(_orbs.size() - 1, -1, -1):
		if not is_instance_valid(_orbs[i]):
			_orbs.remove_at(i)
	return _orbs.size()


func _converge_fx() -> void:
	# sparks pulled into the staff orb during the windup
	FxLib.burst(get_parent(), {
		"amount": 18, "life": 0.45, "explosiveness": 0.3, "v_min": 0.0, "v_max": 0.0,
		"emit_radius": 34.0, "radial_min": -260.0, "radial_max": -180.0,
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.09,
		"ramp": FxLib.fade_ramp(magic_color), "additive": true, "curve": null,
	}, _staff_tip())


func _start_summon() -> void:
	_set_state(State.SUMMONING)
	_summon_fx.emitting = true
	_move_dir = 0.0


func _finish_summon() -> void:
	_summon_fx.emitting = false
	_summon_cd = summon_cooldown * randf_range(0.9, 1.1)
	_set_state(State.MOVE)
	_maybe_teleport_after_cast()
	var world := get_parent()
	var feet := global_position + Vector2(0, _feet)
	var b := OrbBlast.new()
	b.radius = 60.0
	b.color = ghost_color
	b.glow = magic_color
	b.light_energy = 2.5
	b.position = FxLib.to_parent_space(world, feet)
	world.add_child(b)
	get_tree().call_group("player", "add_trauma", 0.15, global_position)
	for i in ghosts_per_summon:
		if _ghosts_alive() >= max_ghosts_alive:
			break
		var g = ghost_scene.instantiate()
		g.start_delay = i * 0.25
		g.rise_height = ghost_rise_height * randf_range(0.85, 1.15)
		g.rise_time = ghost_rise_time
		g.dive_time = ghost_glide_time
		g.haunt_time = ghost_haunt_time
		g.distortion_radius = ghost_distortion_radius
		g.distortion_strength = ghost_distortion_strength
		g.target_restored_areas = ghosts_target_restored_areas
		g.ghost_color = ghost_color
		var offset := Vector2((i - (ghosts_per_summon - 1) * 0.5) * 24.0, 0)
		g.position = FxLib.to_parent_space(world, feet + offset + Vector2(0, -10))
		world.add_child(g)
		_ghosts.append(g)


func _cancel_summon() -> void:
	_summon_fx.emitting = false
	_summon_cd = interrupted_summon_cooldown
	var feet := global_position + Vector2(0, _feet)
	# the circle shatters
	FxLib.burst(get_parent(), {
		"amount": 22, "life": 0.5, "v_min": 150.0, "v_max": 380.0, "direction": Vector2.UP, "spread": 80.0,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.25, "s_max": 0.55, "gravity": Vector2(0, 500),
		"ramp": FxLib.fade_ramp(magic_color), "additive": true,
	}, feet)
	FxLib.burst(get_parent(), {
		"amount": 10, "life": 0.8, "v_min": 20.0, "v_max": 70.0, "gravity": Vector2(0, -40),
		"ramp": FxLib.smoke_ramp(0.5), "s_min": 0.4, "s_max": 0.8, "curve": FxLib.grow(),
	}, feet)


## Teleport away from the player. Returns false if there is nowhere to land.
func _blink_away() -> bool:
	for k in [1.0, 0.7, 0.45]:
		for side in [-_face, _face]:
			var x: float = global_position.x + side * blink_distance * k
			if side == _face and is_instance_valid(_player) and absf(x - float(_player.global_position.x)) < preferred_distance_min:
				continue  # never land on top of the player
			var ground: Variant = _ground_at(x)
			if ground == null:
				continue
			_smoke_puff(global_position)
			global_position = (ground as Vector2) + Vector2(0, -_feet - 4.0)
			velocity = Vector2.ZERO
			_smoke_puff(global_position)
			_blink_cd = blink_cooldown
			_appear = 0.0
			_face_player()
			return true
	return false


## Pressure: being crowded, sharing her surface, sustained fire.
func _update_pressure(delta: float) -> void:
	_pressure = maxf(_pressure - pressure_decay * delta, 0.0)
	if not is_instance_valid(_player) or _state == State.DEAD:
		return
	var d: float = global_position.distance_to(_player.global_position)
	if d < pressure_close_distance:
		_pressure += pressure_close_rate * delta * (1.0 + (pressure_close_distance - d) / pressure_close_distance)
	var mine := _surface_of(global_position)
	if mine >= 0 and mine == _surface_of(_player.global_position):
		_pressure += pressure_same_surface_rate * delta
	_pressure = minf(_pressure, pressure_threshold * 1.5)


func _surface_of(p: Vector2) -> int:
	return _nav.surface_at(p + Vector2(0, _feet), 120.0) if _nav else -1


## While ghosts are out she gets at most one extra action.
func _may_act() -> bool:
	return _ghosts_alive() == 0 or _ghost_actions < 1


func _maybe_teleport_after_cast() -> void:
	if blink_enabled and _blink_cd <= 0.0 and randf() < teleport_after_cast_chance and _may_act():
		_start_teleport()


func debug_state() -> String:
	return "%s p%.2f" % [State.keys()[_state], _pressure]


func _start_teleport() -> void:
	_set_state(State.TELEPORT_TELL)
	if _ghosts_alive() > 0:
		_ghost_actions += 1
	# the tell: rune flare, sparks sucked into her, a crouch then a stretch
	FxLib.flash_light(get_parent(), global_position, magic_color, 2.2, 1.4, teleport_tell)
	_converge_fx()
	_tp_tw = create_tween()
	_tp_tw.tween_property(self, "_tp_scale", Vector2(1.12, 0.9), teleport_tell * 0.7).set_trans(Tween.TRANS_SINE)
	_tp_tw.tween_property(self, "_tp_scale", Vector2(0.7, 1.32), teleport_tell * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _teleport() -> void:
	var dest: Variant = _pick_teleport_spot()
	_blink_cd = blink_cooldown
	_pressure = 0.0
	_set_state(State.MOVE)
	if dest == null:
		if not _blink_away():
			_tp_scale = Vector2.ONE
		return
	# collapse into a streak of ink...
	_smoke_puff(global_position)
	_ink_streak(global_position, dest)
	global_position = dest
	velocity = Vector2.ZERO
	# ...and burst out wide, springing back to shape
	_tp_scale = Vector2(1.5, 0.55)
	_appear = 0.0
	_smoke_puff(global_position)
	_face_player()
	_think_t = 0.35  # a beat to read her new position before she acts


## A board (not hers, not the player's, not recently used) at casting distance.
func _pick_teleport_spot() -> Variant:
	if _nav == null or _nav.surfaces.is_empty() or not is_instance_valid(_player):
		return null
	var mine := _surface_of(global_position)
	var pp: Vector2 = _player.global_position
	var player_surface := _surface_of(pp)
	var ideal := (preferred_distance_min + preferred_distance_max) * 0.5 + 40.0
	var best: Variant = null
	var best_id := -1
	var best_score := INF
	for s in _nav.surfaces:
		var id: int = s["id"]
		if id == mine or id == player_surface or _recent_surfaces.has(id):
			continue
		var l: Vector2 = s["left"]
		var r: Vector2 = s["right"]
		for k in 3:
			var p := l.lerp(r, randf_range(0.2, 0.8))
			var d := p.distance_to(pp)
			var score := absf(d - ideal) + randf() * 60.0
			if d < preferred_distance_min:
				score += 1000.0
			if score < best_score:
				best_score = score
				best = p + Vector2(0, -_feet - 8.0)  # a little above: she drops onto the board
				best_id = id
	if best_id >= 0:
		_recent_surfaces.push_front(best_id)
		while _recent_surfaces.size() > teleport_memory:
			_recent_surfaces.pop_back()
	return best


## Crimson ink arc along the jump so the player can follow where she went.
func _ink_streak(from: Vector2, to: Vector2) -> void:
	var world := get_parent()
	var n := 10
	for i in n:
		var u := float(i) / (n - 1)
		var p := from.lerp(to, u) + Vector2(0, -sin(u * PI) * 60.0)
		FxLib.burst(world, {
			"amount": 3, "life": 0.45 + i * 0.02, "v_min": 10.0, "v_max": 40.0,
			"texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.11, "gravity": Vector2(0, 60),
			"ramp": FxLib.fade_ramp(magic_color), "additive": true, "curve": null,
		}, p)


func _smoke_puff(at: Vector2) -> void:
	var world := get_parent()
	FxLib.burst(world, {
		"amount": 16, "life": 0.7, "v_min": 30.0, "v_max": 110.0, "gravity": Vector2(0, -40),
		"emit_radius": 12.0, "ramp": FxLib.gradient([[0.0, Color(smoke_color, 0.8)], [1.0, Color(smoke_color, 0.0)]]),
		"s_min": 0.4, "s_max": 0.9, "curve": FxLib.grow(), "damp_min": 40.0, "damp_max": 90.0,
	}, at)
	_spark_burst(at, 10, magic_color)
	FxLib.flash_light(world, at, magic_color, 1.8, 1.6, 0.25)


func _spark_burst(at: Vector2, amount: int, color: Color) -> void:
	FxLib.burst(get_parent(), {
		"amount": amount, "life": 0.35, "v_min": 60.0, "v_max": 200.0,
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.1, "damp_min": 150.0, "damp_max": 300.0,
		"ramp": FxLib.fade_ramp(color), "additive": true, "curve": null,
	}, at)


# ---------------------------------------------------------------- taking damage

## Called by player bullets (direct hit).
func take_hit(amount: float, from_pos: Vector2, info := {}) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	FxLib.flash_white(visual)
	_since_hurt = 0.0
	_pressure += pressure_per_hit
	_spark_burst(global_position + Vector2(0, -6), 8, Color(1, 1, 1))
	var was_summoning := _state == State.SUMMONING
	if was_summoning:
		_cancel_summon()
	if health <= 0.0:
		_die()
		return
	if _state == State.TELEPORT_TELL and not HitInfo.staggers(info, amount, stagger_damage):
		return  # small hits do not stop the teleport
	if HitInfo.staggers(info, amount, stagger_damage) or was_summoning:
		velocity.x = signf(global_position.x - from_pos.x) * hurt_knockback
		_set_state(State.HURT)


## Called through the "enemies" group by rocket explosions.
func on_explosion_damage(pos: Vector2, radius: float, damage: float) -> void:
	var dmg := HitInfo.blast_damage(global_position, pos, radius, damage)
	if dmg > 0.0:
		take_hit(dmg, pos, HitInfo.blast(pos))


func _die() -> void:
	_set_state(State.DEAD)
	_summon_fx.emitting = false
	collision_layer = 0
	var world := get_parent()
	if game_data:
		game_data.spawn_drops(world, global_position, drop_table)
	var b := HexBlast.new()
	b.radius = 70.0
	b.color = magic_color
	b.core_color = eye_glow_color
	b.dark_color = smoke_color.darkened(0.5)
	b.light_energy = 3.0
	b.position = position
	world.add_child(b)
	FxLib.smoke_burst(world, global_position, 1.4, smoke_color.darkened(0.3), 22)
	_smoke_puff(global_position)
	FxLib.burst(world, {
		"amount": 30, "life": 1.6, "v_min": 20.0, "v_max": 80.0, "emit_radius": 18.0,
		"gravity": Vector2(0, -70), "texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.12,
		"ramp": FxLib.fade_ramp(magic_color), "additive": true, "curve": null,
	}, global_position)
	get_tree().call_group("player", "add_trauma", 0.3, global_position)
	died.emit()
	var tw := create_tween()
	tw.tween_property(self, "_dissolve", 1.0, 0.6)
	tw.tween_callback(queue_free)


# ---------------------------------------------------------------- visuals

func _process(delta: float) -> void:
	if not View.cull(self, anim):
		return  # off screen: no animation or staff glow (nobody sees it)
	_appear = move_toward(_appear, 1.0, delta * 4.0)
	modulate.a = _appear * (1.0 - _dissolve)
	if _state != State.TELEPORT_TELL:
		_tp_scale = _tp_scale.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	visual.scale = Vector2(_face * _vis_scale.x * _tp_scale.x, _vis_scale.y * _tp_scale.y)
	staff_pivot.rotation = _staff_angle

	# staff orb glow + light follow the tip and brighten while casting
	var summoning := _state == State.SUMMONING
	var glow := _charge + (0.5 if summoning else 0.0)
	if orb_glow is Node2D:
		(orb_glow as Node2D).scale = _orb_glow_scale * (1.0 + glow * orb_glow_growth + 0.06 * sin(Time.get_ticks_msec() * 0.006))
	orb_glow.modulate.a = lerpf(0.3, 0.75, clampf(glow, 0.0, 1.0))
	_light.position = to_local(_staff_tip())
	_light.energy = staff_light_energy * (1.0 + glow * 1.5)

	summon_circle.visible = summoning
	if summoning:
		summon_circle.set("progress", clampf(_state_t / summon_time, 0.0, 1.0))

	_update_animation()


func _update_animation() -> void:
	var wanted := anim_idle
	match _state:
		State.MOVE:
			wanted = anim_walk if absf(velocity.x) > 10.0 else anim_idle
		State.ORB_WINDUP, State.ORB_CASTING:
			# legs keep walking if she casts on the move (the staff still raises in code)
			wanted = anim_walk if absf(velocity.x) > 10.0 else anim_cast
		State.MELEE_WINDUP, State.MELEE_RECOVER:
			wanted = anim_cast
		State.SUMMONING, State.TELEPORT_TELL:
			wanted = anim_summon
		State.HURT:
			wanted = anim_hurt
		State.DEAD:
			return
	if anim.has_animation(wanted) and anim.current_animation != wanted:
		anim.play(wanted)
