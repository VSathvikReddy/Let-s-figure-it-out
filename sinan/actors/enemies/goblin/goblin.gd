extends CharacterBody2D
## Goblin: a platform hunter. With no player near it PATROLS its surface
## (walks, stops, looks around). Once it spots you it runs to striking distance
## - backing off if you are too close - follows you between the hanging boards
## (NavGraph routes: jumps and drops), and attacks from range:
##  - LEAPING STRIKE: crouches (tell), then a long committed jump from far away
##    at where you were - no steering in the air - slashes on landing and
##    follows up with quick lunging slashes, then recovers.
##  - CHARGE: only on the same board / floor with a clear lane: stamps, sprints,
##    one fierce overhead slash, long breather.
## After every jump it settles for a moment and re-reads the situation.
##
## Pack behaviour: every goblin rolls a TEMPERAMENT when it spawns - BOLD
## (attacks often, from close), WARY (hangs back, only commits about half the
## time) or SNEAKY (circles round to the player's other side). And only
## `max_attackers` goblins may be committed to an attack at once (attack
## tokens); the rest keep their distance and wait for an opening, so a pack
## never charges blindly together.
## Pistol shots flash and flinch it but do not stagger it (pistol_knockback_multiplier);
## the machete and rocket blasts do.
##
## Visuals are in goblin.tscn (cut from sinan/assets/sprites/goblin.png):
##   Visual          - flipped / squashed / leaned from code (do not animate it)
##   Visual/Rig      - animated by the AnimationPlayer
##   Rig/WeaponPivot - shoulder holding FrontArm + Sickle
##   Rig/AttackHitbox - Area2D used for every slash
##   AnimationPlayer - idle, run, charge, heavy_windup, heavy, leap_crouch, leap,
##                     slash_a, slash_b, hurt

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const BladeSlash := preload("res://sinan/fx/marks/blade_slash.gd")

enum State {
	IDLE, CHASE, NAV_WALK, NAV_AIR, SETTLE, PATROL,
	CHARGE_WINDUP, CHARGE, HEAVY_WINDUP, HEAVY, LEAP_WINDUP, LEAP, COMBO, RECOVER, HURT, DEAD,
}

signal died

@export_group("Health")
@export var max_health := 12.0
@export var hurt_knockback := 240.0
## Seconds stunned after a staggering hit (cancels windups and combos).
@export var hurt_stun_time := 0.3
## A hit staggers when (damage x multiplier) reaches this. Area blasts need half.
@export var stagger_threshold := 2.5
## Pistol hits count this much toward a stagger (0 = never staggered by the pistol).
@export var pistol_knockback_multiplier := 0.0

@export_group("Movement")
@export var run_speed := 210.0
@export var acceleration := 1400.0
## Must match the NavGraph's gravity so its jump arcs land where planned.
@export var gravity := 1800.0
@export var ledge_check_distance := 20.0
## Body weight for the hanging boards (player = 1).
@export var board_weight := 0.8

## Settle time after landing any jump (random in this range).
@export var settle_time := Vector2(0.2, 0.4)

@export_group("Patrol")
## Walking speed while no player is around.
@export var patrol_speed := 75.0
## Seconds it walks, then seconds it stands and looks around (random ranges).
@export var patrol_walk := Vector2(1.2, 3.0)
@export var patrol_rest := Vector2(0.8, 2.2)

@export_group("Pack")
## Goblins allowed to be mid-attack at the same time (all goblins share this).
@export var max_attackers := 2
## Striking distance it keeps from the player (scaled by temperament); it
## leaps or charges in from here.
@export var hold_distance := 360.0
## Chance per spawn of each temperament: bold, wary, sneaky.
@export var temperament_weights := Vector3(0.4, 0.35, 0.25)

@export_group("Senses")
@export var detection_range := 600.0
@export var give_up_range := 1000.0
@export var attack_gap := 0.4
## How often the route to the player is recomputed (s).
@export var repath_interval := 0.5

@export_group("Charge Attack")
@export var charge_min_distance := 220.0
@export var charge_max_distance := 520.0
@export var charge_cooldown := 4.5
@export var charge_windup := 0.38
@export var charge_speed := 470.0
@export var charge_max_time := 1.3
@export var heavy_range := 50.0
@export var heavy_windup := 0.32
@export var heavy_damage := 2.0
@export var heavy_knockback := 620.0
@export var heavy_recover := 1.1

@export_group("Leaping Strike")
@export var leap_distance_min := 240.0
@export var leap_distance_max := 560.0
@export var leap_cooldown := 2.6
@export_range(0.0, 1.0) var leap_preference := 0.65
@export var leap_windup := 0.42
@export var leap_air_time := 0.75
@export var leap_slam_damage := 1.0

@export_group("Quick Combo")
@export var combo_hits := 3
@export var slash_interval := 0.2
@export var slash_damage := 0.75
@export var slash_knockback := 260.0
@export var slash_lunge := 230.0
@export var combo_recover := 0.7

@export_group("Slash Look")
@export var slash_color := Color(1.0, 0.95, 0.88)
@export var slash_glow := Color(1.0, 0.35, 0.25)
@export var heavy_slash_glow := Color(1.0, 0.55, 0.15)
@export var slash_radius := 30.0
@export var heavy_slash_radius := 46.0
@export var hit_window := 0.12

@export_group("Drops")
@export var drop_table := &"goblin"
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

@export_group("Look")
@export var dust_color := Color(0.6, 0.55, 0.45)
## Squash & stretch strength (0 = off).
@export_range(0.0, 2.0) var squash_amount := 1.0
## Feet height in the goblin's local space (squash pivots here).
@export var feet_y := 21.0

var health := 12.0

enum Mood { BOLD, WARY, SNEAKY }
## Goblins currently holding an attack token (instance id -> true), shared by all.
static var _attack_tokens := {}

@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var attack_hitbox: Area2D = $Visual/Rig/AttackHitbox
@onready var _hit_shape: CollisionShape2D = $Visual/Rig/AttackHitbox/Shape

var _state := State.IDLE
var _state_t := 0.0
var _face := 1.0
var _player
var _nav: NavGraph
var _charge_cd := 1.5
var _leap_cd := 1.5
var _gap := 0.0
var _gap_after := 0.6
var _hits_left := 0
var _slash_t := 0.0
var _swing_down := true
var _hit_t := 0.0
var _hit_done := false
var _hit_damage := 0.0
var _hit_knock := 0.0
var _step_t := 0.0
var _settle_for := 0.3
var _wander_dir := 0.0
var _wander_t := 0.0

# navigation
var _path: Array = []
var _repath_t := 0.0
var _penalties := {}           # link key -> extra cost (decays)
var _patrol_dir := 1.0
var _my_surface := -1

# procedural animation
var _vis_scale := Vector2.ONE
var _sq := Vector2.ONE         # squash / stretch (spring toward 1,1)
var _sq_v := Vector2.ZERO
var _lean := 0.0
var _flinch := 0.0
var _was_floor := true
var _fall_speed := 0.0

# temperament
var _mood := Mood.BOLD
var _cd_mult := 1.0        # attack cooldown multiplier
var _hold := 200.0         # distance kept while waiting for a turn
var _commit_chance := 1.0  # chance to take an opening when it comes
var _flank := 1.0          # side of the player it prefers (-1 / +1)
var _token := false
var _token_idle := 0.0      # time holding a turn without attacking


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	z_index = 2
	set_meta("mass", board_weight)
	_vis_scale = visual.scale.abs()
	_roll_temperament()


## A random personality, so a pack spreads out and takes turns.
func _roll_temperament() -> void:
	var w := temperament_weights
	var r := randf() * (w.x + w.y + w.z)
	_mood = Mood.BOLD if r < w.x else (Mood.WARY if r < w.x + w.y else Mood.SNEAKY)
	match _mood:
		Mood.BOLD:
			_cd_mult = 0.75
			_hold = hold_distance * 0.75
			_commit_chance = 1.0
		Mood.WARY:
			_cd_mult = 1.35
			_hold = hold_distance * 1.25
			_commit_chance = 0.5
		Mood.SNEAKY:
			_cd_mult = 1.0
			_hold = hold_distance
			_commit_chance = 0.8
	_flank = -1.0 if randf() < 0.5 else 1.0
	# everyone starts on a different beat
	_gap = randf_range(0.2, 1.4)
	_leap_cd = randf_range(0.5, 2.5) * _cd_mult
	_charge_cd = randf_range(1.0, 3.0) * _cd_mult


## Ask for one of the shared attack slots. False = someone else's turn.
func _take_token() -> bool:
	if _token:
		return true
	for id in _attack_tokens.keys():
		if not is_instance_id_valid(id):
			_attack_tokens.erase(id)
	if _attack_tokens.size() >= max_attackers:
		return false
	_attack_tokens[get_instance_id()] = true
	_token = true
	return true


func _release_token() -> void:
	if _token:
		_attack_tokens.erase(get_instance_id())
		_token = false


func _exit_tree() -> void:
	_release_token()


func debug_state() -> String:
	return "%s %s%s s%d" % [State.keys()[_state], Mood.keys()[_mood], " *" if _token else "", _my_surface]


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_state_t += delta
	_charge_cd -= delta
	_leap_cd -= delta
	_gap -= delta
	_repath_t -= delta
	# a turn that is not used is given back, so it cannot block the pack
	if _token and _state in [State.CHASE, State.SETTLE, State.PATROL, State.NAV_WALK, State.IDLE]:
		_token_idle += delta
		if _token_idle > 2.0:
			_release_token()
	else:
		_token_idle = 0.0
	for k in _penalties.keys():
		_penalties[k] -= delta * 0.5
		if _penalties[k] <= 0.0:
			_penalties.erase(k)
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_nav):
		_nav = get_tree().get_first_node_in_group("nav_graph")
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y = minf(velocity.y + gravity * delta, 1500.0)

	var to := Vector2.ZERO
	var dist := INF
	if is_instance_valid(_player):
		to = _player.global_position - global_position
		dist = to.length()
	if on_floor and _nav:
		_my_surface = _nav.surface_at(global_position + Vector2(0, feet_y), 30.0)

	match _state:
		State.IDLE:
			_update_wander(dist, delta)
		State.CHASE:
			_update_chase(to, dist, delta)
		State.PATROL:
			_update_patrol(to, dist, delta)
		State.NAV_AIR:
			if on_floor and _state_t > 0.05:
				_land_jump()
		State.NAV_WALK:
			_update_nav_walk(delta)
		State.SETTLE:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
			if _state_t >= _settle_for:
				_set_state(State.CHASE)
		State.CHARGE_WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
			_face_toward(to.x)
			_squash_toward(Vector2(1.08, 0.92), delta)
			if _state_t >= charge_windup:
				_set_state(State.CHARGE)
				_play(&"charge", true)
				_kick(Vector2(0.85, 1.15))
				_dust(10, 1.3)
		State.CHARGE:
			_face_toward(to.x)
			var dir := signf(to.x)
			if on_floor and not _ground_ahead(dir):
				dir = 0.0
			velocity.x = move_toward(velocity.x, dir * charge_speed, acceleration * 2.5 * delta)
			_trail_dust(delta, 0.09)
			if absf(to.x) <= heavy_range and absf(to.y) < 50.0:
				_start_heavy()
			elif _state_t >= charge_max_time or dir == 0.0:
				_start_heavy()
		State.HEAVY_WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * 1.5 * delta)
			_squash_toward(Vector2(0.9, 1.1), delta)
			if _state_t >= heavy_windup:
				_heavy_slash()
		State.HEAVY:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			if _state_t >= 0.35:
				_recover(heavy_recover)
		State.LEAP_WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
			_face_toward(to.x)
			# deep crouch that keeps sinking until it springs - the tell
			_squash_toward(Vector2(1.22, 0.76), delta)
			if _state_t >= leap_windup:
				_launch_leap()
		State.LEAP:
			if on_floor and _state_t > 0.1:
				_land_leap()
		State.COMBO:
			_update_combo(delta)
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			if _state_t >= _gap_after:
				_set_state(State.CHASE)
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * 0.5 * delta)
			if _state_t >= hurt_stun_time:
				_set_state(State.CHASE)

	_update_hit(delta)
	_fall_speed = velocity.y
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not _was_floor and _fall_speed > 250.0:
		_kick(Vector2(1.0 + 0.25 * clampf(_fall_speed / 900.0, 0.0, 1.0), 1.0 - 0.28 * clampf(_fall_speed / 900.0, 0.0, 1.0)))
	_was_floor = now_floor
	_animate_body(delta)


func _set_state(s: State) -> void:
	_state = s
	_state_t = 0.0


func _recover(t: float) -> void:
	_release_token()
	_gap_after = t
	_gap = attack_gap * _cd_mult * randf_range(0.8, 1.4)
	_set_state(State.RECOVER)
	_play(&"idle")


func _play(n: StringName, restart := false) -> void:
	if anim.has_animation(n) and (restart or anim.current_animation != n):
		anim.stop()
		anim.play(n)


func _face_toward(dx: float) -> void:
	if absf(dx) > 2.0:
		_face = signf(dx)


# ---------------------------------------------------------------- deciding

func _player_surface() -> int:
	if _nav == null or not is_instance_valid(_player):
		return -1
	# the surface under the player (searching down, so mid-jump still counts)
	return _nav.surface_at(_player.global_position + Vector2(0, 20), 260.0)


func _same_level(to: Vector2) -> bool:
	if _nav and _my_surface >= 0:
		var ps := _player_surface()
		if ps >= 0:
			return ps == _my_surface
	return absf(to.y) < 70.0


func _update_chase(to: Vector2, dist: float, delta: float) -> void:
	if dist > give_up_range:
		_set_state(State.IDLE)
		return
	_face_toward(to.x)
	var on_floor := is_on_floor()
	var same := _same_level(to)

	# player on another surface: follow a route there
	if not same and on_floor and _nav and _my_surface >= 0:
		_release_token()
		if _repath_t <= 0.0 or _path.is_empty():
			_repath_t = repath_interval
			_path = _nav.find_path(_my_surface, _player_surface(), _penalties)
		if not _path.is_empty():
			_set_state(State.NAV_WALK)
			return
		# no way there: patrol this surface until something changes
		_set_state(State.PATROL)
		return

	# waiting for a turn: keep spacing, circle, step in and out
	if on_floor and same and not _attack_ready(dist):
		_hold_position(to, delta)
		return

	if _gap <= 0.0 and on_floor and same:
		var can_leap := _leap_cd <= 0.0 and dist >= leap_distance_min and dist <= leap_distance_max
		var can_charge := _charge_cd <= 0.0 and dist >= charge_min_distance and dist <= charge_max_distance and _lane_clear(to)
		if (can_leap or can_charge) and not _take_token():
			_hold_position(to, delta)
			return
		if can_leap and (not can_charge or randf() < leap_preference):
			_set_state(State.LEAP_WINDUP)
			_play(&"leap_crouch", true)
			_snarl()
			return
		if can_charge:
			_set_state(State.CHARGE_WINDUP)
			_play(&"heavy_windup", true)
			_snarl()
			return
		if dist < heavy_range * 1.1 and _charge_cd <= 0.0 and _take_token():
			_start_heavy()
			return

	# run to striking distance (backs off when the player is too close)
	if on_floor:
		_hold_position(to, delta)


## May this goblin go in now? Its own turn (token held), or a free slot and
## its temperament says yes. Rolled once per opening, not every frame.
func _attack_ready(dist: float) -> bool:
	if _token:
		return true
	if dist > _hold * 1.6:
		return true  # far away: just close in (it is not an attack yet)
	if _gap > 0.0:
		return false
	if randf() < _commit_chance and _take_token():
		return true   # its turn: the attack checks below run this same frame
	_gap = randf_range(0.3, 0.8)  # not now - roll again a moment later
	return false


## Run to a spot `_hold` px from the player (sneaky ones on the far side) and
## wait there for a leap / charge; backpedals, eyes on the player, if it comes close.
func _hold_position(to: Vector2, delta: float) -> void:
	var side := -signf(to.x) if to.x != 0.0 else _flank
	if _mood == Mood.SNEAKY:
		side = _flank   # works its way round to its favourite side
	var target_x: float = (_player.global_position.x + side * _hold) if is_instance_valid(_player) else global_position.x
	var dx := target_x - global_position.x
	var dir := signf(dx) if absf(dx) > 30.0 else 0.0
	if dir != 0.0 and not _ground_ahead(dir):
		dir = 0.0
	var far := absf(dx) > 160.0
	_face_toward(dx if far else to.x)
	velocity.x = move_toward(velocity.x, dir * (run_speed if far else run_speed * 0.55), acceleration * delta)
	_play(&"run" if absf(velocity.x) > 20.0 else &"idle")
	_trail_dust(delta, 0.18)


## No player around: walk a while, stop and look around, turn at edges and walls.
func _update_wander(dist: float, delta: float) -> void:
	if dist <= detection_range:
		_set_state(State.CHASE)
		_snarl()
		return
	_wander_t -= delta
	if _wander_t <= 0.0:
		if _wander_dir == 0.0:
			_wander_dir = -1.0 if randf() < 0.5 else 1.0
			_wander_t = randf_range(patrol_walk.x, patrol_walk.y)
		else:
			_wander_dir = 0.0
			_wander_t = randf_range(patrol_rest.x, patrol_rest.y)
	if _wander_dir != 0.0 and is_on_floor() and (is_on_wall() or not _ground_ahead(_wander_dir)):
		_wander_dir = -_wander_dir
	if _wander_dir != 0.0:
		_face = _wander_dir
	velocity.x = move_toward(velocity.x, _wander_dir * patrol_speed, acceleration * delta)
	_play(&"run" if absf(velocity.x) > 20.0 else &"idle")


## Shuffle back and forth on this surface (no route to the player).
func _update_patrol(to: Vector2, dist: float, delta: float) -> void:
	if _state_t > 0.8 and (_repath_t <= 0.0):
		_repath_t = repath_interval
		if _same_level(to) or not _nav.find_path(_my_surface, _player_surface(), _penalties).is_empty():
			_set_state(State.CHASE)
			return
	if not _ground_ahead(_patrol_dir):
		_patrol_dir = -_patrol_dir
	# drift toward the player's side and wait there
	if absf(to.x) > 40.0 and signf(to.x) != _patrol_dir and randf() < delta * 1.5:
		_patrol_dir = signf(to.x)
	_face = _patrol_dir
	var speed := run_speed * 0.35 if absf(to.x) > 60.0 else 0.0
	velocity.x = move_toward(velocity.x, _patrol_dir * speed, acceleration * delta)
	_play(&"run" if absf(velocity.x) > 20.0 else &"idle")
	if dist > give_up_range:
		_set_state(State.IDLE)


# ---------------------------------------------------------------- jumps

## Keep a jump on the current surface (never hop off a board by accident).
func _clamp_to_surface(dx: float) -> float:
	if _nav and _my_surface >= 0:
		var s: Dictionary = _nav.surfaces[_my_surface]
		var x := clampf(global_position.x + dx, s["left"].x + 12.0, s["right"].x - 12.0)
		return x - global_position.x
	if not _ground_ahead_at(global_position.x + dx):
		return 0.0
	return dx


func _land_jump() -> void:
	_dust(6, 0.9)
	_settle_for = randf_range(settle_time.x, settle_time.y)
	_set_state(State.SETTLE)
	_play(&"idle", true)


# ---------------------------------------------------------------- navigation

func _update_nav_walk(delta: float) -> void:
	if _path.is_empty():
		_set_state(State.CHASE)
		return
	# the player moved to another surface: re-plan
	if _repath_t <= 0.0:
		_repath_t = repath_interval
		var goal: int = _path[-1]["to"]
		var ps := _player_surface()
		if ps >= 0 and ps != goal:
			_path.clear()
			_set_state(State.CHASE)
			return
	var link: Dictionary = _path[0]
	var start: Vector2 = link["start"]
	var dx := start.x - global_position.x
	if absf(dx) > 8.0:
		_face_toward(dx)
		var dir := signf(dx)
		if not _ground_ahead(dir):
			_path.clear()
			_set_state(State.CHASE)
			return
		velocity.x = move_toward(velocity.x, dir * run_speed, acceleration * delta)
		_play(&"run")
		_trail_dust(delta, 0.18)
		if _state_t > 4.0:  # stuck
			_penalties[link["key"]] = 3.0
			_path.clear()
			_set_state(State.CHASE)
		return
	_path.pop_front()
	_penalties[link["key"]] = _penalties.get(link["key"], 0.0) + 1.5
	if link["type"] == NavGraph.DROP:
		if NavGraph.drop_through(self):
			_set_state(State.NAV_AIR)
			_play(&"leap", true)
			_kick(Vector2(1.1, 0.9))
		else:
			_path.clear()
			_set_state(State.CHASE)
		return
	# committed ballistic jump planned by the NavGraph
	global_position.x = start.x
	velocity = link["vel"]
	_face_toward(velocity.x if absf(velocity.x) > 5.0 else (link["end"].x - start.x))
	_set_state(State.NAV_AIR)
	_play(&"leap", true)
	_kick(Vector2(0.78, 1.25))
	_dust(6, 1.0)


# ---------------------------------------------------------------- charge + heavy slash

func _lane_clear(to: Vector2) -> bool:
	# nothing solid between us, and floor all the way
	var space := get_world_2d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	if _player is CollisionObject2D:
		ex.append(_player.get_rid())
	var from := global_position + Vector2(0, -6)
	if not space.intersect_ray(PhysicsRayQueryParameters2D.create(from, from + Vector2(to.x, 0), 1, ex)).is_empty():
		return false
	var steps := int(absf(to.x) / 60.0)
	for i in range(1, steps):
		if not _ground_ahead_at(global_position.x + signf(to.x) * i * 60.0):
			return false
	return true


func _start_heavy() -> void:
	_charge_cd = charge_cooldown
	_set_state(State.HEAVY_WINDUP)
	_play(&"heavy_windup", true)


func _heavy_slash() -> void:
	_set_state(State.HEAVY)
	_play(&"heavy", true)
	velocity.x = _face * 160.0
	_kick(Vector2(1.3, 0.78))
	_open_hit(heavy_damage, heavy_knockback)
	_spawn_slash(heavy_slash_radius, 18.0, heavy_slash_glow, -125.0, 70.0, 0.32)
	_dust(12, 1.4)
	get_tree().call_group("player", "add_trauma", 0.14, global_position)


# ---------------------------------------------------------------- leap + quick combo

func _launch_leap() -> void:
	_leap_cd = leap_cooldown
	# committed: aimed at where the player is right now, no prediction or steering
	var target: Vector2 = global_position + Vector2(_face * 160.0, 0)
	if is_instance_valid(_player):
		target = _player.global_position
	target.x = global_position.x + _clamp_to_surface(target.x - global_position.x) if _same_level(target - global_position) else target.x
	var t := maxf(leap_air_time, 0.15)
	var d := target - global_position
	velocity = Vector2(clampf(d.x / t, -900.0, 900.0), clampf((d.y - 0.5 * gravity * t * t) / t, -1100.0, 200.0))
	_face_toward(d.x)
	_set_state(State.LEAP)
	_play(&"leap", true)
	_kick(Vector2(0.7, 1.35))
	_dust(10, 1.4)


func _land_leap() -> void:
	_dust(12, 1.3)
	get_tree().call_group("player", "add_trauma", 0.08, global_position)
	_kick(Vector2(1.35, 0.68))
	_swing_down = true
	_quick_slash(leap_slam_damage, slash_knockback)
	_hits_left = maxi(combo_hits, 0)
	_slash_t = slash_interval
	_set_state(State.COMBO)


func _update_combo(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	_slash_t -= delta
	if _slash_t <= 0.0:
		if _hits_left <= 0:
			_recover(combo_recover)
			return
		_hits_left -= 1
		_slash_t = slash_interval
		if is_instance_valid(_player):
			_face_toward(_player.global_position.x - global_position.x)
		if _ground_ahead(_face):
			velocity.x = _face * slash_lunge
		_quick_slash(slash_damage, slash_knockback)


func _quick_slash(damage: float, knockback: float) -> void:
	_play(&"slash_a" if _swing_down else &"slash_b", true)
	_open_hit(damage, knockback)
	_kick(Vector2(1.12, 0.9) if _swing_down else Vector2(0.92, 1.1))
	if _swing_down:
		_spawn_slash(slash_radius, 11.0, slash_glow, -110.0, 55.0, 0.2)
	else:
		_spawn_slash(slash_radius, 11.0, slash_glow, 60.0, -100.0, 0.2)
	_swing_down = not _swing_down
	get_tree().call_group("player", "add_trauma", 0.04, global_position)


# ---------------------------------------------------------------- hitting

func _open_hit(damage: float, knockback: float) -> void:
	_hit_t = hit_window
	_hit_done = false
	_hit_damage = damage
	_hit_knock = knockback
	_hit_shape.set_deferred("disabled", false)


func _update_hit(delta: float) -> void:
	if _hit_t <= 0.0:
		return
	_hit_t -= delta
	if _hit_t <= 0.0:
		_hit_shape.set_deferred("disabled", true)
	if _hit_done or not is_instance_valid(_player):
		return
	var hit: bool = _player in attack_hitbox.get_overlapping_bodies()
	if not hit:
		var d: Vector2 = _player.global_position - global_position
		hit = d.x * _face > -10.0 and d.x * _face < heavy_slash_radius + 20.0 and absf(d.y) < 55.0
	if hit and _player.has_method("take_damage"):
		_hit_done = true
		_player.take_damage(_hit_damage, global_position, _hit_knock, false, self)
		_hit_sparks(_player.global_position)


func _hit_sparks(at: Vector2) -> void:
	FxLib.burst(get_parent(), {
		"amount": 12, "life": 0.3, "v_min": 140.0, "v_max": 340.0, "texture": FxLib.streak(),
		"align": true, "angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
		"direction": Vector2(_face, -0.3), "spread": 50.0,
		"s_min": 0.2, "s_max": 0.45, "damp_min": 300.0, "damp_max": 500.0,
		"ramp": FxLib.fade_ramp(Color(1.0, 0.4, 0.3)), "additive": true,
	}, at)


func _ground_ahead(dir: float) -> bool:
	return _ground_ahead_at(global_position.x + dir * ledge_check_distance)


func _ground_ahead_at(x: float) -> bool:
	var from := Vector2(x, global_position.y)
	var ex: Array[RID] = [get_rid()]
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 60), 1, ex)
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


# ---------------------------------------------------------------- procedural animation

## A sudden squash / stretch that springs back (take-offs, landings, swings).
func _kick(s: Vector2) -> void:
	_sq = Vector2.ONE + (s - Vector2.ONE) * squash_amount
	_sq_v = Vector2.ZERO


## Ease the squash toward a held pose (crouches, wind-ups).
func _squash_toward(s: Vector2, delta: float) -> void:
	var target := Vector2.ONE + (s - Vector2.ONE) * squash_amount
	_sq = _sq.lerp(target, 1.0 - exp(-10.0 * delta))
	_sq_v = Vector2.ZERO


func _animate_body(delta: float) -> void:
	# squash spring (slightly under-damped: a little wobble when it lands)
	var k := 380.0
	var c := 20.0
	_sq_v += ((Vector2.ONE - _sq) * k - _sq_v * c) * delta
	_sq += _sq_v * delta
	# in the air: stretch along the speed
	var air := not is_on_floor() and _state in [State.NAV_AIR, State.LEAP]
	var stretch := Vector2.ONE
	if air:
		var f := clampf(absf(velocity.y) / 900.0, 0.0, 1.0) * 0.12 * squash_amount
		stretch = Vector2(1.0 - f, 1.0 + f)
	# lean into the run, tilt with the arc in the air, flinch back when shot
	var target_lean := clampf(velocity.x / maxf(run_speed, 1.0), -1.6, 1.6) * 0.09
	if air:
		target_lean = clampf(velocity.x / 600.0, -1.0, 1.0) * 0.18 + clampf(velocity.y / 1200.0, -1.0, 1.0) * 0.12 * _face
	_lean = lerpf(_lean, target_lean, 1.0 - exp(-12.0 * delta))
	_flinch = move_toward(_flinch, 0.0, delta * 6.0)
	var s := Vector2(_sq.x * stretch.x, _sq.y * stretch.y)
	visual.scale = Vector2(_face * _vis_scale.x * s.x, _vis_scale.y * s.y)
	visual.position = Vector2(-_face * _flinch * 4.0, feet_y * (1.0 - s.y))
	visual.rotation = _lean - _face * _flinch * 0.18


# ---------------------------------------------------------------- effects

func _spawn_slash(r: float, thick: float, glow: Color, from_deg: float, to_deg: float, life: float) -> void:
	var s := BladeSlash.new()
	s.radius = r
	s.thickness = thick
	s.color = slash_color
	s.glow_color = glow
	s.start_angle = deg_to_rad(from_deg)
	s.end_angle = deg_to_rad(to_deg)
	s.life = life
	var world := get_parent()
	s.position = FxLib.to_parent_space(world, global_position + Vector2(_face * 6.0, -6.0))
	s.scale = Vector2(_face, 1.0)
	world.add_child(s)


func _trail_dust(delta: float, every: float) -> void:
	_step_t -= delta
	if absf(velocity.x) > 100.0 and is_on_floor() and _step_t <= 0.0:
		_step_t = every
		_dust(4, 0.6)


func _dust(amount: int, strength: float) -> void:
	FxLib.burst(get_parent(), {
		"amount": amount, "life": 0.45, "v_min": 30.0 * strength, "v_max": 110.0 * strength,
		"spread": 70.0, "direction": Vector2.UP,
		"ramp": FxLib.gradient([[0.0, Color(dust_color, 0.6)], [1.0, Color(dust_color, 0.0)]]),
		"s_min": 0.12, "s_max": 0.3, "curve": FxLib.grow(), "damp_min": 120.0, "damp_max": 240.0,
	}, global_position + Vector2(0, feet_y - 4.0))


## Red eye-flare before an attack (the player's tell).
func _snarl() -> void:
	var head := global_position + Vector2(_face * 6.0, -24.0)
	FxLib.burst(get_parent(), {
		"amount": 8, "life": 0.3, "v_min": 40.0, "v_max": 110.0, "direction": Vector2.UP, "spread": 60.0,
		"texture": FxLib.glow(), "s_min": 0.04, "s_max": 0.08,
		"ramp": FxLib.fade_ramp(Color(1.0, 0.3, 0.2)), "additive": true, "curve": null,
	}, head)
	FxLib.flash_light(get_parent(), head, Color(1.0, 0.3, 0.2), 1.2, 0.8, 0.3)


# ---------------------------------------------------------------- taking damage

## Called by player bullets and the machete (info: see HitInfo).
func take_hit(amount: float, from_pos: Vector2, info := {}) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	FxLib.flash_white(visual)
	if health <= 0.0:
		_die(from_pos)
		return
	var mult := pistol_knockback_multiplier if info.get("source", &"") == &"pistol" else 1.0
	if not HitInfo.staggers(info, amount, stagger_threshold, mult):
		_flinch = 1.0  # small hits: flash + flinch, no interruption
		return
	# a committed heavy swing / leap is not interrupted, everything else is
	if _state in [State.HEAVY, State.LEAP, State.NAV_AIR]:
		_flinch = 1.0
		return
	_release_token()
	_hit_t = 0.0
	_hit_shape.set_deferred("disabled", true)
	velocity = Vector2(signf(global_position.x - from_pos.x) * hurt_knockback, -120.0)
	_kick(Vector2(0.85, 1.15))
	_set_state(State.HURT)
	_play(&"hurt", true)


## Called through the "enemies" group by rocket explosions.
func on_explosion_damage(pos: Vector2, radius: float, damage: float) -> void:
	var dmg := HitInfo.blast_damage(global_position, pos, radius, damage)
	if dmg > 0.0:
		take_hit(dmg, pos, HitInfo.blast(pos))


func _die(from_pos: Vector2) -> void:
	_release_token()
	_set_state(State.DEAD)
	collision_layer = 0
	died.emit()
	if game_data:
		game_data.spawn_drops(get_parent(), global_position, drop_table)
	anim.stop()
	var away := signf(global_position.x - from_pos.x)
	if away == 0.0:
		away = -_face
	_dust(14, 1.6)
	FxLib.smoke_burst(get_parent(), global_position, 0.8, Color(0.3, 0.32, 0.24), 14)
	get_tree().call_group("player", "add_trauma", 0.15, global_position)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(away * 60.0, -40.0), 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "rotation", away * PI * 1.5, 0.5)
	tw.tween_property(visual, "modulate:a", 0.0, 0.5).set_delay(0.15)
	tw.chain().tween_callback(queue_free)
