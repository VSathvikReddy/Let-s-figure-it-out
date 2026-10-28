extends CharacterBody2D
## Censer Priest: a floating, faceless robed figure with two ember eyes.
## Keeps medium range and glides between nearby boards (it never teleports).
## Each turn it picks ONE target - you, or the painting - and runs a sequence:
##   1. SMOKE ORB: conjured between its sleeves and lobbed in an arc. Where it
##      lands it keeps pouring smoke that slowly fills the area and rises away.
##      Shoot the orb to crack it - its smoke clears fast. Smoke alone is
##      harmless to the painting.
##   2. FIRE BREATH: the hood tilts back (tell), then a stream of fire. Fire
##      ignites the smoke; burning smoke spreads, hurts, and scorches the painting.
## Foreground and painting sequences never overlap.
## Get too close and it answers with a BURST: the robe flares, you are thrown
## back - then it slumps for a moment (recovery: the time to punish it).
##
## Visuals are nodes in priest.tscn (parts from sinan/assets/parts/priest/):
##   Visual          - flipped to face its target (do not animate it)
##   Visual/Rig/Body - animated: lean / sink; Hood, SleeveFront, SleeveBack
##                     rotations; Robe / Stole flare + bias; eye glow; OrbGlow
##   Robe, Stole, Sleeve*/Cloth - ClothStrip nodes (spring cloth driven by code)
##   Hood/Mouth      - where the fire comes from; SleeveFront/Hand - orb spawn
##   FireBreath      - the flame stream (fire_breath.gd), aimed by code
##   AnimationPlayer - idle, glide, cast_windup, throw, breath_tell, breath,
##                     burst_tell, burst, recover, hurt

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const SmokeOrb := preload("res://sinan/actors/enemies/priest/smoke_orb.gd")
const SmokeManager := preload("res://sinan/actors/enemies/priest/smoke_manager.gd")
const HexBlast := preload("res://sinan/fx/blasts/hex_blast.gd")

## Hem height below the collar (robe texture px) - for floating above surfaces.
const ROBE_HEM := 650.0

enum State { FLOAT, MOVE, ORB_WINDUP, ORB_THROW, BREATH_TELL, BREATH, BURST_TELL, BURST, RECOVER, HURT, DEAD }

signal died

@export_group("Health")
@export var max_health := 14.0
@export var stagger_threshold := 3.0
@export var hurt_time := 0.3
## Extra damage taken while it recovers from a burst.
@export var recover_damage_multiplier := 1.5

@export_group("Movement")
## Floats this high above the surface under it (hem to surface).
@export var float_height := 16.0
@export var glide_speed := 150.0
## Keeps between these distances from the player.
@export var preferred_range := Vector2(230, 430)
## Only glides to boards within this distance of where it is.
@export var reposition_radius := 650.0
@export var think_interval := Vector2(1.2, 2.2)

@export_group("Sequences")
## Chance a sequence targets the painting instead of the player.
@export_range(0.0, 1.0) var painting_chance := 0.4
@export var sequence_cooldown := Vector2(2.2, 3.6)
## Seconds the smoke gets to fill the area before the fire comes.
@export var smoke_fill_time := 2.2

@export_group("Smoke Orb")
@export var orb_windup := 0.6
@export var orb_flight_time := 0.95
@export var orb_damage := 0.5

@export_group("Fire Breath")
@export var breath_tell := 0.55
@export var breath_time := 1.1
@export var breath_length := 300.0
@export var breath_angle := 18.0
@export var breath_damage := 0.5

@export_group("Burst")
@export var burst_range := 95.0
@export var burst_tell := 0.22
@export var burst_damage := 0.5
@export var burst_knockback := 620.0
@export var burst_cooldown := 4.0
@export var recover_time := 1.1

@export_group("Look")
@export var magic_color := Color(1.0, 0.5, 0.2)

@export_group("Drops")
@export var drop_table := &"priest"
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

var health := 14.0

var _state := State.FLOAT
var _t := 0.0
var _face := 1.0
var _player
var _nav: NavGraph
var _think := 1.0
var _seq_cd := 1.5
var _burst_cd := 0.0
var _seq_target := &"player"
var _aim_point := Vector2.ZERO
var _move_to := Vector2.ZERO
var _home_y := 0.0
var _vent_id := -1
var _pending_breath := false
var _wait_smoke := 0.0
var _anim_name := &""

@onready var visual: Node2D = $Visual
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var _rig: Node2D = $Visual/Rig
@onready var _robe: Node2D = $Visual/Rig/Body/Robe
@onready var _stole: Node2D = $Visual/Rig/Body/Stole
@onready var _sleeve_f: Node2D = $Visual/Rig/Body/SleeveFront
@onready var _sleeve_b: Node2D = $Visual/Rig/Body/SleeveBack
@onready var _cloth_f: Node2D = $Visual/Rig/Body/SleeveFront/Cloth
@onready var _cloth_b: Node2D = $Visual/Rig/Body/SleeveBack/Cloth
@onready var _hood: Node2D = $Visual/Rig/Body/Hood
@onready var _mouth: Node2D = $Visual/Rig/Body/Hood/Mouth
@onready var _hand: Node2D = $Visual/Rig/Body/SleeveFront/Hand
@onready var _breath: Node2D = $FireBreath


func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	z_index = 2
	set_meta("mass", 0.0)  # it floats: boards do not feel it
	_home_y = global_position.y
	_think = randf_range(think_interval.x, think_interval.y)
	_breath.set("length", breath_length)
	_breath.set("half_angle", deg_to_rad(breath_angle))
	_breath.set("damage", breath_damage)


func debug_state() -> String:
	return "%s %s" % [State.keys()[_state], _seq_target]


func _scale() -> float:
	return _rig.scale.y


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_t += delta
	_seq_cd -= delta
	_burst_cd -= delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(_nav):
		_nav = get_tree().get_first_node_in_group("nav_graph")
	var pp := _player_pos()
	var dist := global_position.distance_to(pp)

	# too close: burst (from any calm state)
	if dist < burst_range and _burst_cd <= 0.0 and _state in [State.FLOAT, State.MOVE, State.ORB_WINDUP]:
		_set_state(State.BURST_TELL)

	match _state:
		State.FLOAT:
			_hover(delta)
			_face_point(pp)
			if _wait_smoke > 0.0:
				# the smoke is filling the area; the fire follows
				_wait_smoke -= delta
				if _wait_smoke <= 0.0:
					_begin_breath()
			else:
				_think -= delta
				if _think <= 0.0:
					_think = randf_range(think_interval.x, think_interval.y)
					_decide(dist)
		State.MOVE:
			_glide(delta)
			if _pending_breath and global_position.distance_to(_breath_target()) <= breath_length * 0.85:
				_pending_breath = false
				_set_state(State.BREATH_TELL)
			elif global_position.distance_to(_move_to) < 10.0 or _t > 3.5:
				if _pending_breath:
					_pending_breath = false
					_set_state(State.BREATH_TELL)
				else:
					_set_state(State.FLOAT)
		State.ORB_WINDUP:
			_hover(delta)
			_face_point(_aim_point)
			if _t >= orb_windup:
				_throw_orb()
		State.ORB_THROW:
			_hover(delta)
			if _t >= 0.45:
				_set_state(State.FLOAT)
				_wait_smoke = smoke_fill_time
		State.BREATH_TELL:
			_hover(delta)
			_aim_point = _breath_target()
			_face_point(_aim_point)
			if _t >= breath_tell:
				_set_state(State.BREATH)
				_breath.call("start")
		State.BREATH:
			_hover(delta)
			# slowly tracks its target, but cannot whip around
			_aim_point = _aim_point.lerp(_breath_target(), 1.0 - exp(-1.5 * delta))
			if _t >= breath_time:
				_breath.call("stop")
				_end_sequence()
		State.BURST_TELL:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			_face_point(pp)
			if _t >= burst_tell:
				_burst()
		State.BURST:
			velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
			if _t >= 0.25:
				_set_state(State.RECOVER)
		State.RECOVER:
			velocity = velocity.move_toward(Vector2.ZERO, 400.0 * delta)
			if _t >= recover_time:
				_set_state(State.FLOAT)
				_think = 0.4
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)
			if _t >= hurt_time:
				_set_state(State.FLOAT)

	move_and_slide()
	NavGraph.keep_above_ground(self, ROBE_HEM * _scale() * 0.5)
	_aim_breath()


func _set_state(s: State) -> void:
	if _state == State.BREATH and s != State.BREATH:
		_breath.call("stop")
	_state = s
	_t = 0.0


func _player_pos() -> Vector2:
	return (_player.global_position as Vector2) if is_instance_valid(_player) else global_position


func _face_point(p: Vector2) -> void:
	if absf(p.x - global_position.x) > 4.0:
		_face = signf(p.x - global_position.x)


# ---------------------------------------------------------------- movement

## Hold position over the surface below (the idle clip adds the float bob).
func _hover(delta: float) -> void:
	var target_y := _float_y(global_position)
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	velocity.y = lerpf(velocity.y, (target_y - global_position.y) * 3.0, 1.0 - exp(-4.0 * delta))


func _glide(delta: float) -> void:
	var to := _move_to - global_position
	var want := to.limit_length(glide_speed)
	if to.length() < 80.0:
		want = to * 1.8
	# arc: rises a little in the middle of a glide
	want.y -= sin(clampf(_t / 1.6, 0.0, 1.0) * PI) * 40.0
	velocity = velocity.lerp(want, 1.0 - exp(-2.5 * delta))
	_face_point(_player_pos())


## Collar height that keeps the hem float_height above the surface under p.
func _float_y(p: Vector2) -> float:
	var hem := ROBE_HEM * _scale()
	var surface_y := _home_y + hem + float_height
	if _nav:
		var id := _nav.surface_at(p, 400.0)
		if id >= 0:
			surface_y = _nav.surfaces[id]["left"].y
	return surface_y - hem - float_height


func _pick_spot() -> Variant:
	if _nav == null:
		return null
	var pp := _player_pos()
	var hem := ROBE_HEM * _scale()
	var best: Variant = null
	var best_score := INF
	for s in _nav.surfaces:
		for k in 3:
			var x: float = lerpf(s["left"].x, s["right"].x, randf_range(0.15, 0.85))
			var p := Vector2(x, s["left"].y - hem - float_height)
			var d_me := p.distance_to(global_position)
			if d_me > reposition_radius or d_me < 60.0:
				continue
			var d := p.distance_to(pp)
			var score := absf(d - (preferred_range.x + preferred_range.y) * 0.5) + d_me * 0.15 + randf() * 50.0
			if score < best_score:
				best_score = score
				best = p
	return best


# ---------------------------------------------------------------- deciding

func _decide(dist: float) -> void:
	if dist < preferred_range.x * 0.8 or dist > preferred_range.y * 1.25:
		var spot: Variant = _pick_spot()
		if spot != null:
			_move_to = spot
			_set_state(State.MOVE)
			return
	if _seq_cd <= 0.0:
		_seq_target = &"painting" if randf() < painting_chance else &"player"
		_aim_point = _orb_target()
		_set_state(State.ORB_WINDUP)
	elif randf() < 0.35:
		var spot: Variant = _pick_spot()
		if spot != null:
			_move_to = spot
			_set_state(State.MOVE)


func _orb_target() -> Vector2:
	var pp := _player_pos()
	if _seq_target == &"player":
		var pv: Vector2 = _player.get("velocity") if is_instance_valid(_player) and _player.get("velocity") != null else Vector2.ZERO
		return pp + pv * 0.3 + Vector2(0, -20)
	# painting: a spot up in the air in front of the painting
	var vp := get_viewport()
	var view := vp.get_visible_rect()
	var to_world := vp.get_canvas_transform().affine_inverse()
	var screen := view.position + Vector2(randf_range(0.3, 0.7) * view.size.x, randf_range(0.18, 0.4) * view.size.y)
	var p := to_world * screen
	if p.distance_to(global_position) > 420.0:
		p = global_position + (p - global_position).limit_length(420.0)
	return p


func _breath_target() -> Vector2:
	var c: Vector2 = SmokeManager.get_for(self).smoke_center(_vent_id) if _vent_id >= 0 else Vector2.INF
	if c != Vector2.INF:
		return c
	if _seq_target == &"player":
		return _player_pos() + Vector2(0, -10)
	return _aim_point


## Glide into range of the smoke first if needed, then breathe.
func _begin_breath() -> void:
	var target := _breath_target()
	if target.distance_to(global_position) > breath_length * 0.9:
		_pending_breath = true
		var back := (global_position - target).normalized()
		_move_to = target + back * breath_length * 0.7
		_move_to.y = minf(_move_to.y, _float_y(_move_to))
		_set_state(State.MOVE)
	else:
		_set_state(State.BREATH_TELL)


func _end_sequence() -> void:
	_seq_cd = randf_range(sequence_cooldown.x, sequence_cooldown.y)
	_vent_id = -1
	_set_state(State.FLOAT)
	_think = randf_range(0.6, 1.2)


# ---------------------------------------------------------------- attacks

func _throw_orb() -> void:
	var o := SmokeOrb.new()
	o.shooter = self
	var from := _hand.global_position
	o.position = FxLib.to_parent_space(get_parent(), from)
	o.target = _aim_point
	o.flight_time = orb_flight_time * clampf(from.distance_to(_aim_point) / 300.0, 0.6, 1.3)
	o.hit_damage = orb_damage
	o.on_vent = func(v: Node2D): _vent_id = int(v.get("vent_id"))
	o.floating = _seq_target == &"painting"
	o.aim()
	get_parent().add_child(o)
	_set_state(State.ORB_THROW)


func _burst() -> void:
	_set_state(State.BURST)
	_burst_cd = burst_cooldown
	var b := HexBlast.new()
	b.radius = burst_range
	b.color = magic_color
	b.core_color = Color(1.0, 0.85, 0.6)
	b.dark_color = Color(0.2, 0.08, 0.06)
	b.light_energy = 2.0
	b.position = FxLib.to_parent_space(get_parent(), global_position + Vector2(0, 20))
	get_parent().add_child(b)
	get_tree().call_group("player", "add_trauma", 0.2, global_position)
	if is_instance_valid(_player) and _player_pos().distance_to(global_position) < burst_range * 1.3 and _player.has_method("take_damage"):
		_player.take_damage(burst_damage, global_position, burst_knockback, false, self)
	SmokeManager.get_for(self).ignite_at(global_position, burst_range)


func _aim_breath() -> void:
	_breath.global_position = _mouth.global_position
	var dir := _aim_point - _breath.global_position
	if dir.length() > 1.0:
		_breath.rotation = dir.angle()


# ---------------------------------------------------------------- animation

func _wanted_anim() -> StringName:
	match _state:
		State.MOVE:
			return &"glide"
		State.ORB_WINDUP:
			return &"cast_windup"
		State.ORB_THROW:
			return &"throw"
		State.BREATH_TELL:
			return &"breath_tell"
		State.BREATH:
			return &"breath"
		State.BURST_TELL:
			return &"burst_tell"
		State.BURST:
			return &"burst"
		State.RECOVER:
			return &"recover"
		State.HURT:
			return &"hurt"
	return &"idle"


func _process(delta: float) -> void:
	if _state == State.DEAD:
		return
	var want := _wanted_anim()
	if want != _anim_name and anim.has_animation(want):
		_anim_name = want
		anim.play(want, 0.0 if want in [&"burst", &"throw"] else 0.15)
	visual.scale = Vector2(_face, 1.0)
	# cloth trails the movement (velocity in its own facing space)
	var local_vx := velocity.x * _face
	_robe.call("drive", local_vx, delta)
	_stole.call("drive", local_vx, delta)
	_cloth_f.call("drive", local_vx * 0.7 + _sleeve_f.rotation * -40.0, delta)
	_cloth_b.call("drive", local_vx * 0.7 + _sleeve_b.rotation * -40.0, delta)


# ---------------------------------------------------------------- damage

func take_hit(amount: float, from_pos: Vector2, info := {}) -> void:
	if _state == State.DEAD:
		return
	if _state == State.RECOVER:
		amount *= recover_damage_multiplier
	health -= amount
	FxLib.flash_white(visual)
	if health <= 0.0:
		_die(from_pos)
		return
	if HitInfo.staggers(info, amount, stagger_threshold) and _state in [State.FLOAT, State.MOVE, State.ORB_WINDUP, State.BREATH_TELL]:
		velocity = (global_position - from_pos).normalized() * 160.0
		_set_state(State.HURT)


func on_explosion_damage(pos: Vector2, radius: float, damage: float) -> void:
	var dmg := HitInfo.blast_damage(global_position, pos, radius, damage)
	if dmg > 0.0:
		take_hit(dmg, pos, HitInfo.blast(pos))


func _die(_from_pos: Vector2) -> void:
	_set_state(State.DEAD)
	_breath.call("stop")
	anim.stop()
	collision_layer = 0
	died.emit()
	var world := get_parent()
	if game_data:
		game_data.spawn_drops(world, global_position, drop_table)
	FxLib.smoke_burst(world, global_position, 1.3, Color(0.2, 0.15, 0.15), 20)
	FxLib.flash_light(world, global_position, magic_color, 2.5, 2.0, 0.4)
	get_tree().call_group("player", "add_trauma", 0.25, global_position)
	# the robe collapses empty: hood drops, cloth crumples and fades
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_hood, "position", _hood.position + Vector2(10, ROBE_HEM * 0.6), 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_hood, "rotation", 1.2, 0.6)
	tw.tween_property(_robe, "scale", Vector2(1.3, 0.25), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_property(_robe, "position", Vector2(0, ROBE_HEM * 0.7), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "modulate:a", 0.0, 0.5).set_delay(0.45)
	tw.chain().tween_callback(queue_free)
