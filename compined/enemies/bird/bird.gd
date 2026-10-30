extends CharacterBody2D
## Knife-taloned bird. Real flapping flight: every DOWNSTROKE of the wings
## pushes it up, the upstroke lets it sink a little. It beats harder and faster
## to climb, slower to come down - it never glides - and folds its wings only
## to dive. It never lands.
##
## Every few seconds it picks one of these:
##  - CLAW CHARGE: backs up (the tell), then lunges at you talons first.
##  - DIVE: climbs high above you, hangs for a moment (the tell), then drops
##    at where you are heading, talons swinging forward at the end.
##  - PAINTING SCRATCH: flies to a well restored part of the painting and
##    rakes a line across it, breaking it again. FLY-BY: a longer, wider rake
##    with its own cooldown.
##  - FEINT (sometimes): heads for the painting, then turns on you instead.
##
## Looks (bird.tscn):
##   Visual            - flipped and pitched by this script
##   Visual/Rig/Torso  - animated by the AnimationPlayer: flap, tuck, strike,
##                       claw_windup, scratch, hurt. "flap" and "scratch" are one
##                       wing beat long and play at the current beat rate.
##   Torso/FrontLeg/Talons - where its strikes and scratches happen
##   ScratchArea       - follows the talons; what the scratch breaks

const Effects := preload("res://compined/common/effects.gd")

## Fraction of the "flap" clip that is the power stroke (matches its keys).
const DOWNSTROKE := 0.42

enum State { FLY, CLAW_WINDUP, CLAW, DIVE_CLIMB, DIVE_HANG, DIVE, RECOVER,
	TO_PAINTING, SCRATCH, FEINT, HURT, DEAD }

@export_group("Health")
## Brush hits it can take (fast and hard to hit, but not tough).
@export var max_health := 4
@export var hurt_knockback := 260.0
@export var hurt_stun_time := 0.35

@export_group("Flight")
@export var gravity := 900.0
## Wing beats per second when hovering; faster to climb, slower to sink.
@export var flap_rate_hover := 2.6
@export var flap_rate_max := 4.4
@export var flap_rate_min := 1.8
@export var max_speed := 300.0
## How hard each beat drives it forward.
@export var thrust := 5.0
@export var drag := 1.4
## Where it hangs around, relative to the player (x mirrors to either side).
@export var hover_offset := Vector2(200, -170)
## Seconds between decisions (random between x and y).
@export var think_interval := Vector2(1.0, 2.0)

@export_group("Attack Choice")
@export var claw_weight := 1.4
@export var dive_weight := 0.8
@export var scratch_weight := 0.8
@export var flyby_weight := 0.4
@export_range(0.0, 1.0) var feint_chance := 0.1
## The player is "exposed" (it prefers attacking them) within this distance.
@export var exposed_range := 420.0
## A painting spot at least this restored (0..1) makes it prefer scratching.
@export_range(0.0, 1.0) var restored_spot_value := 0.5

@export_group("Claw Charge")
@export var claw_range := 400.0
@export var claw_windup := 0.32
@export var claw_speed := 900.0
@export var claw_time := 0.85
## How sharply a lunge or dive bends toward you (radians per second).
@export var homing_turn_rate := 4.5
@export var claw_damage := 1

@export_group("Dive")
@export var dive_height := 250.0
@export var dive_hang := 0.38
@export var dive_speed := 980.0
@export var dive_max_time := 1.4
@export var dive_damage := 1
## 0 = dives at where you are, 1 = at where you will be.
@export_range(0.0, 1.0) var dive_aim_prediction := 0.5

@export_group("Painting Scratch")
@export var fly_to_painting_time := 0.9
@export var scratch_length := 320.0
@export var scratch_time := 1.5
@export var scratch_step := 24.0          ## px between two scratch marks
@export var scratch_radius := 42.0
@export var scratch_damage := 1           ## how much each mark breaks the painting
@export var scratch_max_tilt := 30.0      ## degrees
@export var flyby_length := 520.0
@export var flyby_time := 1.4
@export var flyby_radius := 34.0
@export var flyby_cooldown := 10.0

## How close it may get to the painting's edges, in px.
@export var edge_margin := 50.0

@export_group("Look")
@export var feather_color := Color(0.9, 0.86, 0.82)
@export var death_sound: AudioStream

var health := 0
var state := State.FLY
var _time_in_state := 0.0
var _face := 1.0                  # 1 = looking right
var _side := 1.0                  # which side of the player it hovers on
var _player: Node2D
var _think := 2.0
var _flyby_wait := 5.0
var _target := Vector2.ZERO
var _attack_dir := Vector2.RIGHT
var _hit_done := false
var _hit_at := 0.0

# scratching
var _scratch_from := Vector2.ZERO
var _scratch_dir := Vector2.RIGHT
var _scratch_done := 0.0
var _scratch_length := 240.0
var _scratch_duration := 1.0
var _flyby := false

# wings
var _phase := 0.0                 # 0..1 through one wing beat
var _rate := 2.6                  # wing beats per second right now
var _flapping := true
var _power := 1.0                 # strength of each beat
var _climb_need := 0.0
var _push_x := 0.0
var _smooth_y := 0.0
var _pitch := 0.0
var _anim_name := &""

@onready var health_bar: Node2D = $HealthBar   # the small bar over its head
@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var rig: Node2D = $Visual/Rig
@onready var head: Node2D = $Visual/Rig/Torso/Head
@onready var talons: Node2D = $Visual/Rig/Torso/FrontLeg/Talons
@onready var attack_trail: Line2D = $AttackTrail
@onready var scratch_area: Area2D = $ScratchArea
@onready var _head_home: Vector2 = head.position


func _ready() -> void:
	health = max_health
	health_bar.setup(max_health)
	add_to_group("enemy")
	z_index = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_side = -1.0 if randf() < 0.5 else 1.0
	_think = randf_range(think_interval.x, think_interval.y)
	_phase = randf()
	_smooth_y = global_position.y
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_time_in_state += delta
	_flyby_wait -= delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")

	# the beat clip IS the wing clock: lift is read from where the wings are
	if state in [State.TO_PAINTING, State.SCRATCH]:
		_rate = flap_rate_max * (1.15 if state == State.SCRATCH else 0.9)
	if _anim_name in [&"flap", &"scratch"] and anim.is_playing() and anim.current_animation_length > 0.0:
		_phase = anim.current_animation_position / anim.current_animation_length
	elif _is_beating():
		_phase = fposmod(_phase + _rate * delta, 1.0)

	match state:
		State.FLY:
			_update_fly(delta)
		State.CLAW_WINDUP:
			# back-pedals with strong beats against the direction of the lunge
			_fly_toward(global_position - _attack_dir * 40.0 + Vector2(0, -10), delta, 0.5)
			_face_point(_player_pos())
			if _time_in_state >= claw_windup:
				_start_claw()
		State.CLAW:
			_home_in(delta, homing_turn_rate)
			velocity = velocity.lerp(_attack_dir * claw_speed, 1.0 - exp(-10.0 * delta))
			_check_contact(claw_damage)
			if _attack_over(claw_time):
				_set_state(State.RECOVER)
		State.DIVE_CLIMB:
			var above := _player_pos() + Vector2(-_side * 60.0, -dive_height)
			_fly_toward(above, delta, 1.3)
			if global_position.distance_to(above) < 50.0 or _time_in_state > 2.2:
				_set_state(State.DIVE_HANG)
				_feather_puff()
		State.DIVE_HANG:
			# hangs with big slow beats, wings high - the tell
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			velocity.y += _lift(delta) - gravity * delta
			_face_point(_player_pos())
			if _time_in_state >= dive_hang:
				_start_dive()
		State.DIVE:
			_home_in(delta, homing_turn_rate * 0.7)
			velocity = velocity.move_toward(_attack_dir * dive_speed, 2400.0 * delta)
			_check_contact(dive_damage)
			if _attack_over(dive_max_time):
				_set_state(State.RECOVER)
		State.RECOVER:
			# pulls up with hard beats
			_fly_toward(global_position + Vector2(_face * 120.0, -160.0), delta, 1.4)
			if _time_in_state >= 0.6:
				_set_state(State.FLY)
		State.FEINT:
			_fly_toward(_target, delta, 1.2)
			if _time_in_state >= 0.55:
				_face_point(_player_pos())
				_feather_puff()
				_set_state(State.CLAW_WINDUP)
		State.TO_PAINTING:
			_fly_toward(_scratch_from, delta, 1.4)
			_face_point(_scratch_from)
			if global_position.distance_to(_scratch_from) < 30.0 or _time_in_state > fly_to_painting_time * 2.0:
				_begin_scratch()
		State.SCRATCH:
			_scratch(delta)
			return
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
			velocity.y += gravity * 0.4 * delta
			if _time_in_state >= hurt_stun_time:
				_set_state(State.FLY)
				_kick_flap(260.0)

	# it touches nothing (collision mask 0), so a plain move is enough
	global_position += velocity * delta
	_stay_inside_level()
	if absf(velocity.x) > 30.0 and state in [State.FLY, State.RECOVER, State.CLAW, State.FEINT]:
		_face = signf(velocity.x)


func _set_state(new_state: State) -> void:
	state = new_state
	_time_in_state = 0.0


func _player_pos() -> Vector2:
	return _player.global_position if is_instance_valid(_player) else global_position


func _face_point(point: Vector2) -> void:
	if absf(point.x - global_position.x) > 2.0:
		_face = signf(point.x - global_position.x)


## Never leaves the painting: at an edge it stops going that way.
func _stay_inside_level() -> void:
	var push := Effects.keep_inside_level(self, edge_margin)
	if push.x != 0.0:
		velocity.x = 0.0
	if push.y != 0.0:
		velocity.y = 0.0


# ---------------------------------------------------------------- flight physics

## Lift from the wings this frame. Downstroke = strong push up (peaks in the
## middle of the stroke), upstroke = a slight sink. At the hover beat rate it
## exactly cancels gravity on average.
func _lift(delta: float) -> float:
	if not _flapping:
		return 0.0
	var per_beat := gravity / flap_rate_hover * _power
	if _phase < DOWNSTROKE:
		var stroke := _phase / DOWNSTROKE
		return -per_beat * _rate * sin(PI * stroke) * (PI / (2.0 * DOWNSTROKE)) * delta * 1.08
	return per_beat * _rate * 0.08 * delta


## Flies toward a point by beating its wings. Climbing = faster, harder beats;
## coming down = slower, lighter ones. Forward push comes mostly on the downstroke.
func _fly_toward(point: Vector2, delta: float, urgency := 1.0) -> void:
	var to := point - global_position
	var need := clampf(-to.y / 110.0 + velocity.y / 200.0, -1.5, 1.5)   # + = must climb
	_climb_need = lerpf(_climb_need, need, 1.0 - exp(-6.0 * delta))
	_flapping = true
	var hurry := lerpf(1.0, 1.2, clampf(urgency - 1.0, 0.0, 1.0))
	_rate = clampf(flap_rate_hover * (1.0 + 0.45 * _climb_need) * hurry, flap_rate_min, flap_rate_max)
	_power = clampf(1.0 + 0.35 * _climb_need, 0.45, 1.35)
	velocity.y += _lift(delta) + gravity * delta
	velocity.y = minf(velocity.y, 260.0)

	var wanted_vx := clampf(to.x * 2.2, -max_speed * urgency, max_speed * urgency)
	var stroke_power := 0.35 + 1.3 * (sin(PI * _phase / DOWNSTROKE) if _phase < DOWNSTROKE else 0.0)
	var push := (wanted_vx - velocity.x) * thrust * stroke_power
	_push_x = lerpf(_push_x, push, 1.0 - exp(-8.0 * delta))
	velocity.x += push * delta
	velocity *= exp(-drag * delta * 0.5)
	velocity = velocity.limit_length(max_speed * 1.9 * urgency)


func _is_beating() -> bool:
	if state in [State.TO_PAINTING, State.SCRATCH]:
		return true
	return _flapping and not (state in [State.CLAW, State.DIVE, State.DEAD])


## One big beat (after being hit).
func _kick_flap(strength: float) -> void:
	_phase = 0.0
	_flapping = true
	velocity.y -= strength


# ---------------------------------------------------------------- choosing

func _update_fly(delta: float) -> void:
	if randf() < delta * 0.12:
		_side = -_side
	# drifts around its hover point so it never sits still
	var drift := Vector2(sin(_time_in_state * 0.7 + get_instance_id()) * 60.0, sin(_time_in_state * 1.1) * 30.0)
	_fly_toward(_player_pos() + Vector2(hover_offset.x * _side, hover_offset.y) + drift, delta)
	_think -= delta
	if _think <= 0.0 and is_instance_valid(_player):
		_think = randf_range(think_interval.x, think_interval.y)
		_choose_action()


## Picks an attack at random; some are more likely depending on the situation.
func _choose_action() -> void:
	var distance := global_position.distance_to(_player_pos())
	var exposed := distance < exposed_range
	var spot := _find_restored_spot()
	var tempting: bool = not spot.is_empty() and spot["detail"] >= restored_spot_value

	var options := {}
	if distance < claw_range:
		options["claw"] = claw_weight * (1.6 if exposed else 1.0)
	options["dive"] = dive_weight * (1.4 if exposed else 0.8)
	if not spot.is_empty():
		options["scratch"] = scratch_weight * (1.8 if tempting else 0.7)
		if _flyby_wait <= 0.0:
			options["flyby"] = flyby_weight * (1.6 if tempting else 0.6)

	var total := 0.0
	for option in options:
		total += options[option]
	var roll := randf() * total
	for option in options:
		roll -= options[option]
		if roll > 0.0:
			continue
		match option:
			"claw":
				_start_claw_windup()
			"dive":
				_set_state(State.DIVE_CLIMB)
			"scratch", "flyby":
				if randf() < feint_chance:
					_target = global_position.lerp(spot["position"], 0.5)
					_set_state(State.FEINT)
				else:
					_start_scratch(spot["position"], option == "flyby")
		return


# ---------------------------------------------------------------- claw charge / dive

func _start_claw_windup() -> void:
	_attack_dir = (_player_pos() + Vector2(0, -16) - global_position).normalized()
	_feather_puff()
	_set_state(State.CLAW_WINDUP)


func _start_claw() -> void:
	_attack_dir = (_player_pos() + Vector2(0, -16) - global_position).normalized()
	_face_point(_player_pos())
	velocity = _attack_dir * claw_speed * 0.6
	_hit_done = false
	_flapping = false
	_set_state(State.CLAW)


func _start_dive() -> void:
	var player_velocity: Vector2 = _player.get("velocity") if is_instance_valid(_player) else Vector2.ZERO
	var time_to_reach := global_position.distance_to(_player_pos()) / dive_speed
	var aim := _player_pos() + player_velocity * time_to_reach * dive_aim_prediction + Vector2(0, -12)
	_attack_dir = (aim - global_position).normalized()
	_face_point(aim)
	_hit_done = false
	_flapping = false
	_set_state(State.DIVE)


## A committed attack keeps bending toward the player (limited turn speed).
func _home_in(delta: float, turn_rate: float) -> void:
	if _hit_done:
		return
	var wanted := (_player_pos() + Vector2(0, -16) - talons.global_position).normalized()
	if wanted.dot(_attack_dir) < 0.0:
		return   # already flew past: no U-turns
	var angle := _attack_dir.angle_to(wanted)
	_attack_dir = _attack_dir.rotated(clampf(angle, -turn_rate * delta, turn_rate * delta))
	_face_point(_player_pos())


## An attack ends shortly after it hits, once it has flown past, or on time out.
func _attack_over(max_time: float) -> bool:
	if _hit_done:
		return _time_in_state >= _hit_at + 0.15
	var flew_past := (_player_pos() - global_position).dot(_attack_dir) < -30.0 and _time_in_state > 0.15
	return flew_past or _time_in_state >= max_time


## The talons (or the body) touching the player's body hurt them once.
func _check_contact(damage: int) -> void:
	if _hit_done or not is_instance_valid(_player) or not _player.has_method("take_damage"):
		return
	var player_box := _player_box()
	if player_box.grow(22.0).has_point(talons.global_position) or player_box.grow(14.0).has_point(global_position):
		_hit_done = true
		_hit_at = _time_in_state
		_player.take_damage(damage)
		Effects.burst(_player, 10, Color.WHITE, 0.25, 120.0, 260.0, 2.0, 4.0)


## The player's collision box in the world.
func _player_box() -> Rect2:
	for child in _player.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var size: Vector2 = child.shape.size
			return Rect2(child.global_position - size / 2.0, size)
	return Rect2(_player.global_position - Vector2(16, 16), Vector2(32, 32))


# ---------------------------------------------------------------- painting

## The MOST restored spot on screen (a few random tries), or {} without a painting.
func _find_restored_spot() -> Dictionary:
	var painting := get_tree().get_first_node_in_group("painting")
	if painting == null:
		return {}
	var painting_rect: Rect2 = painting.world_rect()
	var screen_to_world := get_viewport().get_canvas_transform().affine_inverse()
	var screen := get_viewport().get_visible_rect()
	var best := {}
	for i in 8:
		var on_screen := screen.position + Vector2(randf_range(0.2, 0.8), randf_range(0.12, 0.6)) * screen.size
		var spot := screen_to_world * on_screen
		if not painting_rect.has_point(spot):
			continue
		var detail: float = painting.detail_at(spot)
		if best.is_empty() or detail > best["detail"]:
			best = {"position": spot, "detail": detail}
	return best


func _start_scratch(at: Vector2, flyby: bool) -> void:
	_flyby = flyby
	if flyby:
		_flyby_wait = flyby_cooldown
	_scratch_length = flyby_length if flyby else scratch_length
	_scratch_duration = flyby_time if flyby else scratch_time
	var radius := flyby_radius if flyby else scratch_radius
	(scratch_area.get_node("Shape").shape as CircleShape2D).radius = radius
	_scratch_from = at
	_set_state(State.TO_PAINTING)


func _begin_scratch() -> void:
	var tilt := deg_to_rad(randf_range(-scratch_max_tilt, scratch_max_tilt) * (0.5 if _flyby else 1.0))
	_scratch_dir = Vector2.from_angle(tilt) * (1.0 if randf() < 0.5 else -1.0)
	_scratch_from = global_position
	_face = signf(_scratch_dir.x)
	_scratch_done = 0.0
	velocity = Vector2.ZERO
	_set_state(State.SCRATCH)
	_scratch_mark()


## Rakes along a straight line, leaving a mark every `scratch_step` px.
func _scratch(delta: float) -> void:
	var speed := _scratch_length / maxf(_scratch_duration, 0.05)
	var before := _scratch_done
	_scratch_done = minf(_scratch_done + speed * delta, _scratch_length)
	var progress := _scratch_done / _scratch_length
	# dips a little in the middle of the rake
	global_position = _scratch_from + _scratch_dir * _scratch_done + Vector2(0, sin(progress * PI) * 10.0)
	if Effects.keep_inside_level(self, edge_margin) != Vector2.ZERO:
		_scratch_done = _scratch_length   # reached the edge of the painting: the rake ends here
	if int(_scratch_done / scratch_step) > int(before / scratch_step):
		_scratch_mark()
	if _scratch_done >= _scratch_length:
		velocity = Vector2(_face * 120.0, -60.0)
		_set_state(State.FLY)


func _scratch_mark() -> void:
	scratch_area.global_position = talons.global_position
	Effects.paint(scratch_area, -scratch_damage)
	Effects.burst(scratch_area, 4, feather_color, 0.35, 30.0, 90.0, 2.0, 4.0)


# ---------------------------------------------------------------- animation

## Which clip fits what the body is doing right now.
func _wanted_anim() -> StringName:
	match state:
		State.CLAW_WINDUP:
			return &"claw_windup"
		State.CLAW:
			return &"strike"
		State.DIVE:
			# folded for the drop, talons out just before it reaches you
			return &"strike" if _player_pos().distance_to(global_position) < 170.0 else &"tuck"
		State.SCRATCH:
			return &"scratch"
		State.HURT:
			return &"hurt"
	return &"flap"


func _process(delta: float) -> void:
	rotation = 0.0   # the body never rolls; all tilt is on the rig
	attack_trail.emitting = (state in [State.CLAW, State.DIVE] and not _hit_done) or state == State.SCRATCH
	if state == State.DEAD:
		return
	var wanted := _wanted_anim()
	if wanted != _anim_name and anim.has_animation(wanted):
		_anim_name = wanted
		anim.play(wanted, 0.12)
	# beat clips play at the current beat rate (one clip = one beat)
	if _anim_name in [&"flap", &"scratch"]:
		anim.speed_scale = _rate * anim.current_animation_length
	else:
		anim.speed_scale = 1.0

	# body pitch: nose down when diving or fast, up when climbing hard or braking
	var target_pitch := 0.0
	match state:
		State.DIVE:
			target_pitch = clampf(_attack_dir.y, -1.0, 1.0) * (0.25 if _anim_name == &"strike" else 0.9)
		State.CLAW:
			target_pitch = clampf(_attack_dir.y, -1.0, 1.0) * 0.3
		State.DIVE_HANG, State.CLAW_WINDUP:
			target_pitch = -0.2
		State.SCRATCH, State.HURT:
			target_pitch = 0.0
		_:
			var speed := clampf(absf(velocity.x) / max_speed, 0.0, 1.0)
			target_pitch = lerpf(-0.28, 0.08, speed) + clampf(velocity.y / 700.0, -0.5, 0.6) * 0.3 \
				+ clampf(_push_x / 2500.0, -1.0, 1.0) * 0.12
	_pitch = lerp_angle(_pitch, target_pitch, 1.0 - exp(-9.0 * delta))
	_pitch = clampf(wrapf(_pitch, -PI, PI), -1.0, 1.0)   # never upside down
	visual.scale = Vector2(_face, 1.0)
	visual.rotation = _pitch * _face

	# the head stays steady while the body bobs (like a real bird)
	_smooth_y = lerpf(_smooth_y, global_position.y, 1.0 - exp(-7.0 * delta))
	_smooth_y = clampf(_smooth_y, global_position.y - 6.0, global_position.y + 6.0)
	var bob := (global_position.y - _smooth_y) if _is_beating() else 0.0
	head.position = _head_home + Vector2(0, -bob * 0.6 / maxf(rig.scale.y, 0.01))


func _feather_puff() -> void:
	Effects.burst(self, 8, feather_color, 0.5, 40.0, 120.0, 3.0, 6.0)


# ---------------------------------------------------------------- damage

## Called by the brush.
func take_damage(damage: int) -> void:
	if state == State.DEAD:
		return
	health -= damage
	health_bar.show_health(health)
	_feather_puff()
	visual.modulate = Color(5, 5, 5)
	create_tween().tween_property(visual, "modulate", Color.WHITE, 0.15)
	if health <= 0:
		_die()
		return
	if state == State.SCRATCH:
		return   # keeps scratching
	velocity = (global_position - _player_pos()).normalized() * hurt_knockback
	_flapping = false
	_set_state(State.HURT)


func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	Effects.play_sound(self, death_sound)
	Effects.burst(self, 16, feather_color, 0.9, 60.0, 200.0, 3.0, 7.0)
	var away := signf(global_position.x - _player_pos().x)
	if away == 0.0:
		away = -_face
	var fall := create_tween().set_parallel(true)
	fall.tween_property(self, "position", position + Vector2(away * 50.0, 120.0), 0.6).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "rotation", away * PI * 2.0, 0.6)
	fall.tween_property(visual, "modulate:a", 0.0, 0.6).set_delay(0.2)
	fall.chain().tween_callback(queue_free)
