extends CharacterBody2D
## Knife-taloned bird. Physics-driven flight: every DOWNSTROKE of the wings
## pushes the bird up (real lift, so each flap visibly carries it), the
## upstroke folds the wings and it sinks a little. It flaps harder and faster
## to climb, slowly and lightly to come down - it never glides - and folds
## them only to dive.
##
## Behaviour (picks between these every few seconds):
##  - CLAW CHARGE: rears back, then lunges at you - chest back, talons first.
##  - DIVE: climbs high above you, hangs for a moment (the tell), folds and
##    drops at where you are heading, swings its talons forward just before
##    it reaches you, pulls up after.
##  - PAINTING SCRATCH: flies into the painting and rakes a line of small
##    distortions; FLY-BY SCRATCH: a longer, wider pass (own cooldown).
##  - FEINT (~10%): heads for the painting, then turns on you.
## It never lands - always on the wing.
## While inside the painting only painting shots can hurt it.
##
## Visuals are nodes in bird.tscn (parts from sinan/assets/parts/bird/):
##   Visual            - flipped and pitched by code (do not animate it)
##   Visual/Rig/Torso  - animated by the AnimationPlayer: wings, tail, legs, head
##   Torso/FrontLeg/Talons - Marker2D at the claw tip: strikes hit from here
##   Torso/*Wing       - skinned wings: Skeleton2D with Arm + Hand bones, so the
##                       wing bends at the wrist (tip lags, folds on the upstroke)
##   AnimationPlayer   - flap, tuck, strike, claw_windup, land,
##                       scratch, hurt. "flap" and "scratch" are 1-cycle loops the
##                       script scrubs in step with the physics, so each
##                       downstroke you key is the one that lifts the bird.
##   Head:position is set by code (keeps the head steady); key its rotation only.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const BladeSlash := preload("res://sinan/fx/marks/blade_slash.gd")
const DepthFlight := preload("res://sinan/painting/depth_flight.gd")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")


# rig measurements in part-image pixels (where its feet are)
const BODY_CENTER := Vector2(181, 138)
const HIP := Vector2(190, 222)
const LEG_LENGTH := 278.0
## Fraction of the "flap" clip that is the power stroke (keep in sync with its keys).
const DOWNSTROKE := 0.42

enum State { FLY, CLAW_WINDUP, CLAW, DIVE_CLIMB, DIVE_HANG, DIVE, RECOVER,
	TO_CANVAS, SCRATCH, FROM_CANVAS, FEINT, HURT, DEAD }

signal died

@export_group("Health")
@export var max_health := 5.0
@export var hurt_knockback := 260.0
@export var hurt_stun_time := 0.35

@export_group("Flight")
## Size of the bird (part images are scaled by this).
@export var gravity := 900.0
## Wing beats per second when hovering; climbing beats up to max.
@export var flap_rate_hover := 2.6
@export var flap_rate_max := 4.4
@export var flap_rate_min := 1.8
## Top cruising speed and how hard each flap drives it forward.
@export var max_speed := 300.0
@export var thrust := 5.0
## Air drag (per second).
@export var drag := 1.4
## Where it hangs around relative to the player (x mirrors to its side).
@export var hover_offset := Vector2(200, -170)
@export var think_interval := Vector2(1.0, 2.0)

@export_group("Attack Choice")
@export var claw_weight := 1.4
@export var dive_weight := 0.8
@export var scratch_weight := 0.8
@export var flyby_weight := 0.4
## Chance that a painting run is a feint at the player instead.
@export_range(0.0, 1.0) var feint_chance := 0.1
## Player counts as "exposed" (bird prefers attacking it) within this range.
@export var exposed_range := 420.0
## A painting spot this clean (0 = untouched) or cleaner makes it prefer the painting.
@export_range(0.0, 1.0) var clean_spot_value := 0.45

@export_group("Claw Charge")
@export var claw_range := 400.0
@export var claw_windup := 0.32
@export var claw_speed := 900.0
## Longest a lunge keeps chasing before it gives up (it ends early on a hit
## or once it has flown past you).
@export var claw_time := 0.85
## How sharply a committed lunge / dive bends toward you (radians per second).
@export var homing_turn_rate := 4.5
@export var claw_damage := 1.0
@export var claw_knockback := 340.0

@export_group("Dive")
@export var dive_height := 250.0
@export var dive_hang := 0.38
@export var dive_speed := 980.0
@export var dive_max_time := 1.4
@export var dive_damage := 1.0
@export var dive_knockback := 400.0
@export_range(0.0, 1.0) var dive_aim_prediction := 0.5

@export_group("Painting Scratch")
@export var canvas_fly_time := 0.9
@export var scratch_length := 320.0
@export var scratch_time := 1.5
@export var scratch_step := 24.0
@export var scratch_radius := 42.0
@export var scratch_strength := 0.9
@export var scratch_max_tilt := 30.0
## Fly-by: longer, wider pass with its own cooldown.
@export var flyby_length := 520.0
@export var flyby_time := 1.4
@export var flyby_radius := 34.0
@export var flyby_cooldown := 10.0
@export var painting_size := 2.2
@export var painting_hit_radius := 24.0

@export_group("Look")
@export var slash_color := Color(1.0, 0.95, 0.9)
@export var slash_glow := Color(0.85, 0.85, 1.0)
@export var scratch_color := Color(0.15, 0.1, 0.12)
@export var feather_color := Color(0.9, 0.86, 0.82)

@export_group("Drops")
@export var drop_table := &"bird"
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

var health := 5.0

var _state := State.FLY
var _t := 0.0
var _face := 1.0
var _side := 1.0
var _player
var _nav: NavGraph
var _think := 2.0
var _flyby_cd := 5.0
var _target := Vector2.ZERO
var _attack_dir := Vector2.RIGHT
var _hit_done := false
var _hit_at := 0.0
var _flyby := false

var _flight: DepthFlight
var _canvas_tw: Tween   # the flight back out of the painting
var _layer: Node2D
var _scratch_from := Vector2.ZERO
var _scratch_dir := Vector2.RIGHT
var _scratch_done := 0.0
var _scratch_len := 240.0
var _scratch_dur := 1.0
var _scratch_r := 26.0
var _home: Node
var _layer_bits := 2

# flight / animation state
var _phase := 0.0          # 0..1 wing-beat cycle
var _rate := 2.6           # beats per second right now
var _flapping := true
var _power := 1.0           # strength of each beat (lighter when coming down)
var _climb_need := 0.0
var _ax := 0.0
var _smooth_y := 0.0
var _pitch := 0.0
var _anim_name := &""

@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var _rig: Node2D = $Visual/Rig
@onready var _head: Node2D = $Visual/Rig/Torso/Head
@onready var _talons: Node2D = $Visual/Rig/Torso/FrontLeg/Talons
@onready var _trail: Line2D = get_node_or_null("AttackTrail")
@onready var _head_home: Vector2 = $Visual/Rig/Torso/Head.position


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("ghosts")  # receives on_painting_shot() while inside the painting
	health = max_health
	z_index = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	set_meta("mass", 0.35)
	_layer_bits = collision_layer
	_side = -1.0 if randf() < 0.5 else 1.0
	_think = randf_range(think_interval.x, think_interval.y)
	_phase = randf()
	_smooth_y = global_position.y
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS


func debug_state() -> String:
	return "%s %.1fHz" % [State.keys()[_state], _rate if _flapping else 0.0]


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_t += delta
	_flyby_cd -= delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_nav):
		_nav = get_tree().get_first_node_in_group("nav_graph")
	# the beat clip plays at `_rate` beats per second and IS the wing clock:
	# lift is read from where the wings are in the clip, so the two always match
	if _state in [State.TO_CANVAS, State.SCRATCH, State.FROM_CANVAS]:
		_rate = flap_rate_max * (1.15 if _state == State.SCRATCH else 0.9)
	if _anim_name in [&"flap", &"scratch"] and anim.active and anim.is_playing() and anim.current_animation_length > 0.0:
		_phase = anim.current_animation_position / anim.current_animation_length
	elif _is_beating():
		_phase = fposmod(_phase + _rate * delta, 1.0)

	match _state:
		State.FLY:
			_update_fly(delta)
		State.CLAW_WINDUP:
			# back-pedal: strong flaps against the direction of the lunge
			_fly_toward(global_position - _attack_dir * 40.0 + Vector2(0, -10), delta, 0.5)
			_face_point(_player_pos())
			if _t >= claw_windup:
				_start_claw()
		State.CLAW:
			_home_in(delta, homing_turn_rate)
			velocity = velocity.lerp(_attack_dir * claw_speed, 1.0 - exp(-10.0 * delta))
			_check_contact(claw_damage, claw_knockback)
			if _attack_over(claw_time):
				_set_state(State.RECOVER)
		State.DIVE_CLIMB:
			var above := _player_pos() + Vector2(-_side * 60.0, -dive_height)
			_fly_toward(above, delta, 1.3)
			if global_position.distance_to(above) < 50.0 or _t > 2.2:
				_set_state(State.DIVE_HANG)
				_snap_fx(global_position)
		State.DIVE_HANG:
			# hangs with big slow beats, wings high - the tell
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			velocity.y += _lift(delta) - gravity * delta
			_face_point(_player_pos())
			if _t >= dive_hang:
				_start_dive()
		State.DIVE:
			_home_in(delta, homing_turn_rate * 0.7)
			velocity = velocity.move_toward(_attack_dir * dive_speed, 2400.0 * delta)
			_check_contact(dive_damage, dive_knockback)
			if _attack_over(dive_max_time):
				_set_state(State.RECOVER)
		State.RECOVER:
			# pull up with hard beats
			_fly_toward(global_position + Vector2(_face * 120.0, -160.0), delta, 1.4)
			if _t >= 0.6:
				_set_state(State.FLY)
		State.FEINT:
			_fly_toward(_target, delta, 1.2)
			if _t >= 0.55:
				_face_point(_player_pos())
				_set_state(State.CLAW_WINDUP)
				_snap_fx(global_position)
		State.TO_CANVAS:
			velocity = Vector2.ZERO
			var done := _flight.step(delta)
			rotation = 0.0  # the flight helper aims its node along the path; the bird pitches its rig instead
			if done:
				_begin_scratch()
			return
		State.SCRATCH:
			_scratch(delta)
			return
		State.FROM_CANVAS:
			return
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
			velocity.y += gravity * 0.4 * delta
			if _t >= hurt_stun_time:
				_set_state(State.FLY)
				_kick_flap(260.0)

	# it collides with nothing (mask 0), so a plain move does what move_and_slide
	# would, without the physics motion test every frame
	global_position += velocity * get_physics_process_delta_time()
	_keep_above_floor()
	if absf(velocity.x) > 30.0 and _state in [State.FLY, State.RECOVER, State.CLAW, State.FEINT]:
		_face = signf(velocity.x)


func _set_state(s: State) -> void:
	_state = s
	_t = 0.0


func _player_pos() -> Vector2:
	return (_player.global_position as Vector2) if is_instance_valid(_player) else global_position


func _face_point(p: Vector2) -> void:
	if absf(p.x - global_position.x) > 2.0:
		_face = signf(p.x - global_position.x)


# ---------------------------------------------------------------- flight physics

## Lift from the wings this frame (velocity change). Downstroke = strong push
## up, peaking mid-stroke; upstroke = slight sink. Averages to `gravity` at the
## hover rate, more when beating faster.
func _lift(delta: float) -> float:
	if not _flapping:
		return 0.0
	var per_beat := gravity / flap_rate_hover * _power   # velocity gained per beat
	if _phase < DOWNSTROKE:
		var u := _phase / DOWNSTROKE
		return -per_beat * _rate * sin(PI * u) * (PI / (2.0 * DOWNSTROKE)) * delta * 1.08
	return per_beat * _rate * 0.08 * delta  # upstroke: a little sink


## Fly toward a point by beating the wings - it never glides. Climbing means
## faster, harder beats; coming down means slower, lighter ones (less lift than
## gravity). Thrust is applied mostly on the downstroke.
func _fly_toward(target: Vector2, delta: float, urgency := 1.0) -> void:
	var to := target - global_position
	# vertical need: + = must climb (above us or falling)
	var need := clampf(-to.y / 110.0 + velocity.y / 200.0, -1.5, 1.5)
	_climb_need = lerpf(_climb_need, need, 1.0 - exp(-6.0 * delta))
	_flapping = true
	_rate = clampf(flap_rate_hover * (1.0 + 0.45 * _climb_need) * lerpf(1.0, 1.2, clampf(urgency - 1.0, 0.0, 1.0)),
		flap_rate_min, flap_rate_max)
	_power = clampf(1.0 + 0.35 * _climb_need, 0.45, 1.35)
	velocity.y += _lift(delta) + gravity * delta
	velocity.y = minf(velocity.y, 260.0)
	# horizontal: drive toward the target speed, mostly during the power stroke
	var want_vx := clampf(to.x * 2.2, -max_speed * urgency, max_speed * urgency)
	var power := 1.0
	power = 0.35 + 1.3 * (sin(PI * _phase / DOWNSTROKE) if _phase < DOWNSTROKE else 0.0)
	var ax := (want_vx - velocity.x) * thrust * power
	_ax = lerpf(_ax, ax, 1.0 - exp(-8.0 * delta))
	velocity.x += ax * delta
	velocity *= exp(-drag * delta * 0.5)
	velocity = velocity.limit_length(max_speed * 1.9 * urgency)


## Wings beating (visually inside the painting too).
func _is_beating() -> bool:
	if _state in [State.TO_CANVAS, State.SCRATCH, State.FROM_CANVAS]:
		return true
	return _flapping and not (_state in [State.CLAW, State.DIVE, State.DEAD])


## One big beat (take-off, recovering from a hit).
func _kick_flap(strength: float) -> void:
	_phase = 0.0
	_flapping = true
	velocity.y -= strength


## It flies through the world (no collisions), so never sink into the floor
## or leave the frame.
func _keep_above_floor() -> void:
	if _nav == null or _nav.surfaces.is_empty():
		return
	if NavGraph.keep_above_ground(self, _feet_offset() + 6.0):
		velocity.y = minf(velocity.y, -40.0)
		if _state == State.DIVE:
			# skims along the ground instead of giving up
			_attack_dir = Vector2(signf(_attack_dir.x) if _attack_dir.x != 0.0 else _face, minf(_attack_dir.y, 0.0)).normalized()
	var r := _nav.air_rect().grow(140.0)
	global_position.x = clampf(global_position.x, r.position.x, r.end.x)
	global_position.y = maxf(global_position.y, r.position.y)


func _feet_offset() -> float:
	return (HIP.y - BODY_CENTER.y + LEG_LENGTH) * _rig.scale.y


# ---------------------------------------------------------------- choosing

func _hover_point() -> Vector2:
	var p := _player_pos() + Vector2(hover_offset.x * _side, hover_offset.y)
	if _nav:
		var r := _nav.air_rect()
		p = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p


func _update_fly(delta: float) -> void:
	if randf() < delta * 0.12:
		_side = -_side
	# drift around the hover point so it never sits still
	var wander := Vector2(sin(_t * 0.7 + get_instance_id()) * 60.0, sin(_t * 1.1) * 30.0)
	_fly_toward(_hover_point() + wander, delta)
	_think -= delta
	if _think <= 0.0 and is_instance_valid(_player) and _player.is_alive():
		_think = randf_range(think_interval.x, think_interval.y)
		_choose_action()


func _choose_action() -> void:
	var pp := _player_pos()
	var dist := global_position.distance_to(pp)
	var exposed: bool = dist < exposed_range or (_player is CharacterBody2D and not (_player as CharacterBody2D).is_on_floor())
	var spot := _pick_canvas_spot()
	var clean: bool = not spot.is_empty() and float(spot.get("value", 1.0)) <= clean_spot_value
	var options := {}
	if dist < claw_range:
		options["claw"] = claw_weight * (1.6 if exposed else 1.0)
	options["dive"] = dive_weight * (1.4 if exposed else 0.8)
	if not spot.is_empty():
		options["scratch"] = scratch_weight * (1.8 if clean else 0.7)
		if _flyby_cd <= 0.0:
			options["flyby"] = flyby_weight * (1.6 if clean else 0.6)
	var total := 0.0
	for k in options:
		total += options[k]
	var roll := randf() * total
	for k in options:
		roll -= options[k]
		if roll <= 0.0:
			match k:
				"claw":
					_start_claw_windup()
				"dive":
					_set_state(State.DIVE_CLIMB)
				"scratch", "flyby":
					if randf() < feint_chance:
						_start_feint(spot)
					else:
						_start_canvas(spot, k == "flyby")
			return


# ---------------------------------------------------------------- claw charge / dive

func _start_claw_windup() -> void:
	_attack_dir = (_player_pos() + Vector2(0, -16) - global_position).normalized()
	_set_state(State.CLAW_WINDUP)
	_snap_fx(global_position)


func _start_claw() -> void:
	# committed: aimed where the player is at launch
	_attack_dir = (_player_pos() + Vector2(0, -16) - global_position).normalized()
	_face_point(_player_pos())
	velocity = _attack_dir * claw_speed * 0.6
	_hit_done = false
	_flapping = false
	_set_state(State.CLAW)
	_slash_fx(global_position, _attack_dir, 22.0)


func _start_dive() -> void:
	var pp := _player_pos()
	var pv: Vector2 = _player.get("velocity") if is_instance_valid(_player) and _player.get("velocity") != null else Vector2.ZERO
	var t := global_position.distance_to(pp) / dive_speed
	var target := pp + pv * t * dive_aim_prediction + Vector2(0, -12)
	_attack_dir = (target - global_position).normalized()
	_face_point(target)
	_hit_done = false
	_flapping = false
	_set_state(State.DIVE)
	_slash_fx(global_position, _attack_dir, 20.0)


## Committed attacks keep bending toward the player (limited turn rate).
func _home_in(delta: float, turn_rate: float) -> void:
	if _hit_done:
		return
	var want := (_player_pos() + Vector2(0, -16) - _talons.global_position).normalized()
	if want.dot(_attack_dir) < 0.0:
		return  # already past: no U-turns, it follows through
	var ang := _attack_dir.angle_to(want)
	_attack_dir = _attack_dir.rotated(clampf(ang, -turn_rate * delta, turn_rate * delta))
	_face_point(_player_pos())


## An attack ends after the hit (short follow-through), once it has flown past
## the player, or when its time runs out.
func _attack_over(max_time: float) -> bool:
	if _hit_done:
		return _t >= _hit_at + 0.15
	var to := _player_pos() - global_position
	var passed := to.dot(_attack_dir) < -30.0 and _t > 0.15
	return passed or _t >= max_time


func _check_contact(damage: float, knock: float) -> void:
	if _hit_done or not is_instance_valid(_player):
		return
	# the claws do the damage: talon tip (or the bird's body) against the
	# player's whole collision box
	var near := HitInfo.near_body(_player, _talons.global_position, 22.0) 		or HitInfo.near_body(_player, global_position, 14.0)
	if near and _player.has_method("take_damage"):
		_hit_done = true
		_hit_at = _t
		_player.take_damage(damage, global_position, knock, false, self)
		# three parallel claw rakes
		for k in 3:
			_slash_fx(_player_pos() + Vector2(0, -22 + k * 9), _attack_dir.rotated(0.35), 22.0)


# ---------------------------------------------------------------- painting

## A visible, as-clean-as-possible spot of the painting (with its mask value).
func _pick_canvas_spot() -> Dictionary:
	var vp := get_viewport()
	var view_to_world := vp.get_canvas_transform().affine_inverse()
	var view := vp.get_visible_rect()
	var best := {}
	var best_value := INF
	for attempt in 8:
		var screen := view.position + Vector2(randf_range(0.2, 0.8) * view.size.x, randf_range(0.12, 0.5) * view.size.y)
		var pick := PaintPicker.pick(get_parent(), view_to_world * screen)
		if pick.is_empty():
			continue
		var layer = pick["layer"]
		var value: float = layer.distortion_at(pick["local"]) if layer.has_method("distortion_at") else 0.0
		if value < best_value:
			best_value = value
			best = pick
			best["value"] = value
	return best


func _start_feint(spot: Dictionary) -> void:
	# fly toward where the painting spot is on screen... then turn on the player
	_target = global_position.lerp(spot.get("world", global_position + Vector2(_face * 200.0, -100.0)), 0.5)
	if not spot.has("world"):
		_target = global_position + Vector2(_face * 180.0, -120.0)
	_set_state(State.FEINT)


func _start_canvas(spot: Dictionary, flyby: bool) -> void:
	_flyby = flyby
	if flyby:
		_flyby_cd = flyby_cooldown
	_scratch_len = flyby_length if flyby else scratch_length
	_scratch_dur = flyby_time if flyby else scratch_time
	_scratch_r = flyby_radius if flyby else scratch_radius
	var p := spot.duplicate()
	p["scale"] = minf(float(spot["scale"]) * painting_size, 1.0)
	_flight = DepthFlight.new(self, global_position, p, Vector2.ZERO, canvas_fly_time, 50.0)
	_home = get_parent()
	collision_layer = 0  # flying into the painting: studio shots pass under it
	_set_state(State.TO_CANVAS)


func _begin_scratch() -> void:
	_layer = _flight.layer
	if not is_instance_valid(_layer):
		_return_from_canvas()
		return
	reparent(_layer)  # moves with the parallax while it scratches
	z_as_relative = true
	z_index = 0  # drawn inside this painting layer, so layers in front cover it
	_scratch_from = _flight.local
	var tilt := deg_to_rad(randf_range(-scratch_max_tilt, scratch_max_tilt) * (0.5 if _flyby else 1.0))
	_scratch_dir = Vector2.from_angle(tilt) * (1.0 if randf() < 0.5 else -1.0)
	_face = signf(_scratch_dir.x)
	_scratch_done = 0.0
	_set_state(State.SCRATCH)
	_stamp()


func _scratch(delta: float) -> void:
	var speed := _scratch_len / maxf(_scratch_dur, 0.05)
	var before := _scratch_done
	_scratch_done = minf(_scratch_done + speed * delta, _scratch_len)
	# a slight dip into the canvas at the middle of the rake
	var u := _scratch_done / _scratch_len
	position = _scratch_from + _scratch_dir * _scratch_done + Vector2(0, sin(u * PI) * 10.0)
	if int(_scratch_done / scratch_step) > int(before / scratch_step):
		_stamp()
	if _scratch_done >= _scratch_len:
		_return_from_canvas()


func _stamp() -> void:
	if not is_instance_valid(_layer):
		return
	var claw := _layer.to_local(_talons.global_position)
	Paint.hit(self, _layer, claw, _scratch_r, scratch_strength, Paint.Kind.SCRATCH, &"bird")
	var marks := ClawMarks.new()
	marks.color = scratch_color
	marks.dir = _scratch_dir
	marks.size = _scratch_r * 0.75
	marks.lines = 2
	marks.position = claw  # where the claws are, not the body
	_layer.add_child(marks)
	FxLib.burst(_layer, {
		"amount": 4, "life": 0.35, "v_min": 30.0, "v_max": 90.0, "gravity": Vector2(0, 200),
		"s_min": 0.05, "s_max": 0.1, "ramp": FxLib.fade_ramp(feather_color), "curve": null,
	}, global_position)


func _return_from_canvas() -> void:
	_set_state(State.FROM_CANVAS)
	var world := _home if is_instance_valid(_home) else get_tree().current_scene
	reparent(world)
	z_as_relative = true
	z_index = 3
	_canvas_tw = create_tween().set_parallel(true)
	_canvas_tw.tween_property(self, "global_position", _hover_point(), canvas_fly_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_canvas_tw.tween_property(self, "scale", Vector2.ONE, canvas_fly_time)
	_canvas_tw.chain().tween_callback(func():
		if _state == State.DEAD:
			return  # died on the way out: stay without a hitbox
		collision_layer = _layer_bits
		if _state == State.FROM_CANVAS:
			velocity = Vector2(_face * 120.0, -60.0)
			_set_state(State.FLY))


func on_painting_shot(layer: Node, local: Vector2, radius: float) -> void:
	if _state != State.SCRATCH or layer != _layer:
		return
	if local.distance_to(position) <= painting_hit_radius + radius * 0.5:
		take_hit(2.0, global_position + Vector2(0, -20))


# ---------------------------------------------------------------- animation

## Which AnimationPlayer clip fits what the body is doing right now.
func _wanted_anim() -> StringName:
	match _state:
		State.CLAW_WINDUP:
			return &"claw_windup"
		State.CLAW:
			return &"strike"
		State.DIVE:
			# folded for the drop, talons swing out just before it reaches you
			return &"strike" if _player_pos().distance_to(global_position) < 170.0 else &"tuck"
		State.SCRATCH:
			return &"scratch"
		State.HURT:
			return &"hurt"
	return &"flap"


func _process(delta: float) -> void:
	if visual == null or not View.cull(self, anim):
		return  # off screen: no animation (the wing clock runs in physics)
	rotation = 0.0  # body never rolls over; all tilt is done on the rig (clamped below)
	if _trail:
		_trail.emitting = (_state in [State.CLAW, State.DIVE] and not _hit_done) or _state == State.SCRATCH
	if _state == State.DEAD:
		return
	var want := _wanted_anim()
	if want != _anim_name and anim.has_animation(want):
		_anim_name = want
		anim.play(want, 0.12)
	# beat clips run at the current beat rate (one clip = one beat)
	if _anim_name in [&"flap", &"scratch"]:
		anim.speed_scale = _rate * anim.current_animation_length
	else:
		anim.speed_scale = 1.0

	# body pitch: nose down when diving / speeding, up when climbing hard or braking
	var target_pitch := 0.0
	match _state:
		State.DIVE:
			target_pitch = clampf(_attack_dir.y, -1.0, 1.0) * (0.25 if _anim_name == &"strike" else 0.9)
		State.CLAW:
			target_pitch = clampf(_attack_dir.y, -1.0, 1.0) * 0.3   # the strike clip throws the chest back
		State.DIVE_HANG, State.CLAW_WINDUP:
			target_pitch = -0.2
		State.SCRATCH, State.HURT:
			target_pitch = 0.0
		_:
			# slow / hovering: body upright (wings sweep more horizontally);
			# fast: body levels out and leans into the flight
			var speed := clampf(absf(velocity.x) / max_speed, 0.0, 1.0)
			target_pitch = lerpf(-0.28, 0.08, speed) + clampf(velocity.y / 700.0, -0.5, 0.6) * 0.3 				+ clampf(_ax / 2500.0, -1.0, 1.0) * 0.12
	_pitch = lerp_angle(_pitch, target_pitch, 1.0 - exp(-9.0 * delta))
	_pitch = clampf(wrapf(_pitch, -PI, PI), -1.0, 1.0)  # never past ~57 degrees: no upside-down
	visual.scale = Vector2(_face, 1.0)
	visual.rotation = _pitch * _face

	# head stays steady while the body bobs (like a real bird)
	_smooth_y = lerpf(_smooth_y, global_position.y, 1.0 - exp(-7.0 * delta))
	_smooth_y = clampf(_smooth_y, global_position.y - 6.0, global_position.y + 6.0)
	var bob := (global_position.y - _smooth_y) if _is_beating() else 0.0
	_head.position = _head_home + Vector2(0, -bob * 0.6 / maxf(_rig.scale.y, 0.01))


# ---------------------------------------------------------------- effects

func _slash_fx(at: Vector2, dir: Vector2, r: float) -> void:
	var s := BladeSlash.new()
	s.radius = r
	s.thickness = 8.0
	s.color = slash_color
	s.glow_color = slash_glow
	s.start_angle = deg_to_rad(-70.0)
	s.end_angle = deg_to_rad(70.0)
	s.life = 0.2
	var world := get_parent()
	s.position = FxLib.to_parent_space(world, at)
	s.rotation = dir.angle()
	world.add_child(s)


## Feather puff + a shriek flash (the tell before lunges and dives).
func _snap_fx(at: Vector2) -> void:
	FxLib.burst(get_parent(), {
		"amount": 8, "life": 0.5, "v_min": 40.0, "v_max": 120.0, "gravity": Vector2(0, 160),
		"s_min": 0.08, "s_max": 0.16, "spin_min": -200.0, "spin_max": 200.0,
		"ramp": FxLib.fade_ramp(feather_color), "curve": null,
	}, at)
	FxLib.flash_light(get_parent(), at, Color(1.0, 0.95, 0.9), 1.0, 0.8, 0.25)


# ---------------------------------------------------------------- damage

func take_hit(amount: float, from_pos: Vector2, info := {}) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	FxLib.flash_white(visual)
	_snap_fx(global_position)
	if health <= 0.0:
		_die(from_pos)
		return
	if _state in [State.SCRATCH, State.TO_CANVAS, State.FROM_CANVAS]:
		return  # keeps going; painting hits still hurt
	if not HitInfo.staggers(info, amount, 0.9):
		return
	velocity = (global_position - from_pos).normalized() * hurt_knockback
	_flapping = false
	_set_state(State.HURT)


func on_explosion_damage(pos: Vector2, radius: float, damage: float) -> void:
	if collision_layer == 0:
		return
	var dmg := HitInfo.blast_damage(global_position, pos, radius, damage)
	if dmg > 0.0:
		take_hit(dmg, pos, HitInfo.blast(pos))


func _die(from_pos: Vector2) -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	if _canvas_tw:
		_canvas_tw.kill()  # its fall below owns the position now
	died.emit()
	var world := get_parent()
	if world is Parallax2D and is_instance_valid(_home):
		reparent(_home)
		world = _home
	if game_data:
		game_data.spawn_drops(world, global_position, drop_table)
	FxLib.smoke_burst(world, global_position, 0.7, Color(0.75, 0.72, 0.7), 12)
	FxLib.burst(world, {
		"amount": 16, "life": 0.9, "v_min": 60.0, "v_max": 200.0, "gravity": Vector2(0, 220),
		"s_min": 0.08, "s_max": 0.18, "spin_min": -300.0, "spin_max": 300.0,
		"ramp": FxLib.fade_ramp(feather_color), "curve": null,
	}, global_position)
	get_tree().call_group("player", "add_trauma", 0.12, global_position)
	var away := signf(global_position.x - from_pos.x)
	if away == 0.0:
		away = -_face
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(away * 50.0, 120.0), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "rotation", away * PI * 2.0, 0.6)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3)  # back to full size if it died in depth
	tw.tween_property(visual, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(queue_free)
