extends CharacterBody2D
## One bat of a BatFlock. 1 HP: a single pistol shot kills it, but there are
## many and they move as a swarm - area damage (rocket blasts) is the counter
## and scatters the whole flock.
## Visuals are nodes in bat.tscn (parts from sinan/assets/parts/bat/):
##   Visual          - leaned / scaled by code (banking, painting depth)
##   Visual/Rig      - WingL, WingR, Body, Head: animated by the AnimationPlayer
##   Visual/EyeGlow  - red glow before and during a dive pass (set by code)
##   AnimationPlayer - "flap" (one beat; the script scrubs it in step with the
##                     physics so each downstroke you key lifts the bat) and
##                     "dive" (wings swept back). Head:rotation is set by code
##                     (ears trailing on a spring) - key its scale only.
## Each bat beats at its own slightly different rate so the swarm never moves
## in lockstep. Spawned and steered by bat_flock.gd.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
## Fraction of the "flap" clip that is the power stroke (keep in sync with its keys).
const DOWNSTROKE := 0.45

signal died

var flock: Node           # the BatFlock steering this bat
var gravity := 600.0
var flap_rate := 8.0
var contact_damage := 0.12
var contact_knockback := 60.0
var color_tint := Color.WHITE

## Set by the flock.
var desired := Vector2.ZERO     # where the flock wants this bat
var attacking := false          # in a dive pass: touching the player hurts
var alert := false              # eyes glow before a pass
var depth := 1.0                # < 1 while the flock is "inside" the painting
var hit_this_pass := false
var scattered := 0.0            # > 0: tumbling away after a blast, ignores the flock
var tight_follow := false       # in an attack stream: stick to its spot on the path

var _phase := 0.0
var _dead := false
var _ear := 0.0
var _ear_w := 0.0
var _lean := 0.0
var _anim_name := &""

@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var _wing_l: Sprite2D = $Visual/Rig/WingL
@onready var _wing_r: Sprite2D = $Visual/Rig/WingR
@onready var _head: Node2D = $Visual/Rig/Head
@onready var _eye_glow: Sprite2D = $Visual/EyeGlow
@onready var _trail: Line2D = get_node_or_null("AttackTrail")


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("swarm")  # the flock counts as one enemy for spawn limits
	z_index = 3
	_phase = randf()
	flap_rate *= randf_range(0.85, 1.2)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	visual.modulate = color_tint


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# the flap clip is the wing clock (it plays at flap_rate beats per second)
	if _anim_name == &"flap" and anim.active and anim.is_playing() and anim.current_animation_length > 0.0:
		_phase = anim.current_animation_position / anim.current_animation_length
	else:
		_phase = fposmod(_phase + flap_rate * delta, 1.0)
	# lift: strong on the downstroke, a little sink on the upstroke (avg = gravity)
	var lift := 0.0
	if _phase < DOWNSTROKE:
		lift = -gravity * sin(PI * _phase / DOWNSTROKE) * (PI / (2.0 * DOWNSTROKE)) * 1.06
	else:
		lift = gravity * 0.05
	velocity.y += (lift + gravity) * delta
	if scattered > 0.0:
		scattered -= delta
		velocity *= exp(-2.0 * delta)
	elif tight_follow:
		# attack stream: track its point on the leader's path closely (the wing
		# lift above still makes it bob)
		var want := ((desired - global_position) * 14.0).limit_length(1000.0)
		velocity = velocity.lerp(want, 1.0 - exp(-18.0 * delta))
	else:
		# springy steering toward the spot the flock wants (k_p / k_d)
		var to := desired - global_position
		velocity += (to * 9.0 - velocity * 3.2) * delta
		if View.sees(self, global_position, 120.0):
			velocity += _separation() * delta  # spacing only matters where you can see it
	velocity = velocity.limit_length(1000.0 if tight_follow else 720.0)
	global_position += velocity * delta
	# never below the ground: skim along it and bounce back up
	if NavGraph.keep_above_ground(self, 16.0):
		velocity.y = minf(velocity.y, -120.0)
	if attacking:
		_check_contact()


func _separation() -> Vector2:
	if flock == null:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for b in flock.bats:
		if b == self or not is_instance_valid(b):
			continue
		var d: Vector2 = global_position - b.global_position
		var l := d.length()
		if l < 24.0 and l > 0.01:
			push += d / l * (24.0 - l) * 40.0
	return push


func _check_contact() -> void:
	if hit_this_pass or flock == null:
		return
	var p = flock.player()
	if not is_instance_valid(p):
		return
	if HitInfo.near_body(p, global_position, 14.0):
		hit_this_pass = true
		p.take_damage(contact_damage, global_position, contact_knockback, false, self)
		FxLib.burst(get_parent(), {
			"amount": 6, "life": 0.25, "v_min": 100.0, "v_max": 240.0, "texture": FxLib.streak(),
			"align": true, "angle_min": 0.0, "angle_max": 0.0, "spin_min": 0.0, "spin_max": 0.0,
			"s_min": 0.15, "s_max": 0.3, "ramp": FxLib.fade_ramp(Color(1.0, 0.4, 0.5)), "additive": true,
		}, p.global_position)


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if visual == null or _dead or not View.cull(self, anim, 120.0):
		return  # off screen: no animation (the wing clock runs in physics)
	var want := &"dive" if attacking else &"flap"
	if want != _anim_name and anim.has_animation(want):
		_anim_name = want
		anim.play(want, 0.08)
		if want == &"flap":
			anim.seek(_phase * anim.current_animation_length, true)  # each bat off-beat
	# one clip = one beat, so the clip runs at flap_rate beats per second
	anim.speed_scale = flap_rate * anim.current_animation_length if _anim_name == &"flap" else 1.0
	# head / ears: a spring that lags behind the motion
	var target := clampf(velocity.y / 500.0, -0.6, 0.6) * 0.25 + clampf(velocity.x / 700.0, -1.0, 1.0) * 0.2
	_ear_w += ((target - _ear) * 260.0 - _ear_w * 14.0) * delta
	_ear += _ear_w * delta
	_head.rotation = _ear
	# bank into turns
	_lean = lerpf(_lean, clampf(velocity.x / 600.0, -1.0, 1.0) * 0.35, 1.0 - exp(-8.0 * delta))
	visual.rotation = _lean
	visual.scale = Vector2.ONE * depth
	visual.modulate = color_tint.darkened((1.0 - depth) * 0.9)
	_eye_glow.modulate.a = move_toward(_eye_glow.modulate.a, 0.9 if alert or attacking else 0.0, delta * 5.0)
	if _trail:
		_trail.emitting = (attacking and not hit_this_pass) or depth < 0.95


# ---------------------------------------------------------------- damage

func take_hit(_amount: float, from_pos: Vector2, info := {}) -> void:
	if _dead:
		return
	if HitInfo.is_area(info) and flock:
		flock.scatter(from_pos)
	_die(from_pos)


func on_explosion_damage(pos: Vector2, radius: float, _damage: float) -> void:
	if _dead or collision_layer == 0:
		return
	var d := global_position.distance_to(pos)
	if flock and d < radius * 2.9:
		flock.scatter(pos)
	if d <= radius * 1.3:
		_die(pos)


## Blasted away from a point; tumbles for a moment before rejoining.
func knock_away(from: Vector2, strength: float) -> void:
	var dir := (global_position - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	velocity = dir.rotated(randf_range(-0.6, 0.6)) * strength
	scattered = randf_range(0.7, 1.1)


func _die(from_pos: Vector2) -> void:
	_dead = true
	anim.stop()  # the wings are about to leave the rig
	collision_layer = 0
	died.emit()
	var world := get_parent()
	FxLib.smoke_burst(world, global_position, 0.35, Color(0.25, 0.2, 0.3), 6)
	FxLib.flash_light(world, global_position, Color(0.8, 0.5, 1.0), 0.8, 0.6, 0.15)
	# the two wings tumble away, the body drops
	var away := (global_position - from_pos).normalized()
	for w: Sprite2D in [_wing_l, _wing_r]:
		w.reparent(world)
		var g: Vector2 = w.global_position
		var side := -1.0 if w == _wing_l else 1.0
		var tw: Tween = w.create_tween().set_parallel(true)
		tw.tween_property(w, "global_position", g + Vector2(side * 40.0 + away.x * 30.0, 80.0), 0.7).set_ease(Tween.EASE_IN)
		tw.tween_property(w, "rotation", w.rotation + side * TAU, 0.7)
		tw.tween_property(w, "modulate:a", 0.0, 0.7)
		tw.chain().tween_callback(w.queue_free)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", global_position + Vector2(away.x * 20.0, 60.0), 0.5).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "rotation", PI * 1.5, 0.5)
	tw.tween_property(visual, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(queue_free)
