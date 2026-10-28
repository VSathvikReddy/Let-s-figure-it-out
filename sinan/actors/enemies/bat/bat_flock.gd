extends Node2D
## A flock of bats. Released by the Forger's portals (or placed for a scripted
## event). A violet glow warns for a moment, then 6-12 bats stream out.
##
## Between attacks the flock is a loose cloud circling above the player.
## Attacks are a STREAM: the leader flies a path and every bat follows that
## exact path a moment behind the one before it - a snake of bats, easy to
## read and every bat gets its own go:
##   PLAYER_TELL - bunches up, red eyes, screech flash
##   STREAM      - dives through the player (the leader keeps homing in until
##                 it is past). Every bat that touches you hurts (a little),
##                 once per pass - no immunity window between bats.
##   PAINT_TELL  - flies over the cleanest bit of painting nearby, violet glow
##   PAINT_RUN   - the stream dives INTO the canvas at that point: each bat
##                 shrinks as it reaches the entry point, rakes claw scratches
##                 along the sweep, then climbs back out the same way.
## Spreading too far makes it regroup. Area damage (rocket blasts) scatters it
## and cancels the current attack; survivors regroup.

const FxLib := preload("res://sinan/fx/core/fx_lib.gd")
const BatScene := preload("res://sinan/actors/enemies/bat/bat.tscn")
const PaintPicker := preload("res://sinan/painting/paint_picker.gd")

enum State { WARN, EMERGE, GATHER, REGROUP, PLAYER_TELL, STREAM, PAINT_TELL, PAINT_RUN, SCATTER, DONE }

signal died

@export var bat_count := Vector2i(6, 12)
@export var warn_time := 0.8
@export var emerge_time := 1.0
@export var warn_color := Color(0.75, 0.4, 1.0)

@export_group("Flock")
## Radius of the loose cloud around the leader.
@export var flock_radius := 70.0
@export var cruise_speed := 260.0
## Regroup when bats average further than this from the leader.
@export var max_spread := 210.0
@export var gather_time := Vector2(1.0, 2.0)
@export var gather_offset := Vector2(170, -190)
## Physics frames between one bat and the next in an attack stream.
@export_range(1, 12) var stream_gap_frames := 4

@export_group("Attack: Player")
@export var tell_time := 0.5
@export var pass_speed := 600.0
## How far past the player the stream keeps going.
@export var pass_overshoot := 220.0
## How sharply the stream bends toward the player (radians per second).
@export var homing_turn_rate := 3.0
@export var pass_max_time := 2.4
## Damage per bat that touches the player (each bat once per pass).
@export var contact_damage := 0.12

@export_group("Attack: Painting")
@export_range(0.0, 1.0) var paint_attack_chance := 0.45
@export var paint_tell_time := 0.6
## Length of the sweep inside the painting and its speed.
@export var paint_length := 380.0
@export var paint_speed := 340.0
## Bat size inside the painting (depth).
@export var paint_depth := 0.5
## Every bat rakes a scratch this often (px of its own path), this big.
@export var paint_step := 34.0
@export var paint_radius := 30.0
@export var paint_strength := 0.7
@export var scratch_color := Color(0.12, 0.08, 0.14)

@export_group("Scatter")
@export var scatter_strength := 520.0
@export var scatter_time := 1.0

@export_group("Drops")
@export var drop_table := &"bat"
@export var game_data: GameData = preload("res://sinan/systems/data/game_data.tres")

var bats: Array = []

var _state := State.WARN
var _t := 0.0
var _lead := Vector2.ZERO
var _lead_vel := Vector2.ZERO
var _side := 1.0
var _gather_for := 2.0
var _dir := Vector2.RIGHT
var _past := 0.0
var _to_spawn := 8
var _spawned := 0
var _offsets: Array[Vector2] = []
var _tight := 1.0
var _player

# the leader's recent path (newest last): where each bat in a stream flies to,
# and whether that point was inside the painting
var _trail := PackedVector2Array()
var _trail_in := PackedByteArray()
const TRAIL_MAX := 160

# painting run
var _entry := Vector2.ZERO
var _run_phase := 0          # 0 = diving to the entry, 1 = raking, 2 = climbing out
var _run_from := Vector2.ZERO
var _in_canvas := false
var _last_stamp := {}        # bat -> position of its last scratch


func _ready() -> void:
	add_to_group("bat_flocks")
	z_index = 3
	_to_spawn = randi_range(bat_count.x, bat_count.y)
	_lead = global_position
	_side = -1.0 if randf() < 0.5 else 1.0


func player() -> Node2D:
	return _player


func debug_state() -> String:
	return "%s %d bats" % [State.keys()[_state], bats.size()]


func _physics_process(delta: float) -> void:
	_t += delta
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	for i in range(bats.size() - 1, -1, -1):
		if not is_instance_valid(bats[i]) or bats[i].get("_dead"):
			bats.remove_at(i)
			_offsets.remove_at(i)
	if _state >= State.GATHER and bats.is_empty() and _spawned >= _to_spawn:
		_finish()
		return
	var pp: Vector2 = _player.global_position if is_instance_valid(_player) else _lead

	match _state:
		State.WARN:
			if _t >= warn_time:
				_set_state(State.EMERGE)
		State.EMERGE:
			var want := int(ceil(_t / emerge_time * _to_spawn))
			while _spawned < mini(want, _to_spawn):
				_spawn_bat()
			_move_lead(global_position + Vector2(0, -60), cruise_speed * 0.5, delta)
			if _spawned >= _to_spawn:
				_to_gather()
		State.GATHER:
			var p := pp + Vector2(gather_offset.x * _side, gather_offset.y) \
				+ Vector2(sin(_t * 1.3) * 80.0, sin(_t * 2.1) * 30.0)
			_move_lead(_clamp_air(p), cruise_speed, delta)
			_tight = lerpf(_tight, 1.0, 1.0 - exp(-3.0 * delta))
			if _spread() > max_spread:
				_set_state(State.REGROUP)
			elif _t >= _gather_for:
				if not (randf() < paint_attack_chance and _start_paint_tell()):
					_start_player_tell()
		State.REGROUP:
			_move_lead(_centroid(), cruise_speed * 0.4, delta)
			_tight = lerpf(_tight, 0.6, 1.0 - exp(-3.0 * delta))
			if _spread() < max_spread * 0.55 or _t > 2.5:
				_to_gather(0.6)
		State.PLAYER_TELL:
			_lead_vel = _lead_vel.move_toward(Vector2.ZERO, 900.0 * delta)
			_lead += _lead_vel * delta
			_tight = lerpf(_tight, 0.4, 1.0 - exp(-8.0 * delta))
			if _t >= tell_time:
				_dir = (pp + Vector2(0, -20) - _lead).normalized()
				_past = 0.0
				_begin_stream(true)
				_set_state(State.STREAM)
		State.STREAM:
			# keeps bending toward the player until it is past them
			var to_p := pp + Vector2(0, -20) - _lead
			if to_p.dot(_dir) > 0.0:
				var ang := _dir.angle_to(to_p.normalized())
				_dir = _dir.rotated(clampf(ang, -homing_turn_rate * delta, homing_turn_rate * delta))
			else:
				_past += pass_speed * delta
			_lead_vel = _dir * pass_speed
			_lead += _lead_vel * delta
			# done once the LAST bat has gone past too
			if _past >= pass_overshoot + bats.size() * stream_gap_frames * pass_speed / 60.0 or _t >= pass_max_time:
				_end_stream()
		State.PAINT_TELL:
			_move_lead(_entry + Vector2(-_dir.x * 160.0, -170.0), cruise_speed * 1.4, delta)
			_tight = lerpf(_tight, 0.45, 1.0 - exp(-8.0 * delta))
			if _t >= paint_tell_time:
				_run_phase = 0
				_begin_stream(false)
				_set_state(State.PAINT_RUN)
		State.PAINT_RUN:
			_update_paint_run(delta)
		State.SCATTER:
			_lead_vel = _lead_vel.move_toward(Vector2.ZERO, 400.0 * delta)
			_lead += _lead_vel * delta
			if _t >= scatter_time:
				_lead = _centroid()
				_set_state(State.REGROUP)

	# the leader stays above the ground (a stream skims along it)
	var nav := NavGraph.current
	if nav:
		var limit: float = nav.floor_y() - 45.0
		if _lead.y > limit:
			_lead.y = limit
			_lead_vel.y = minf(_lead_vel.y, 0.0)
			if _state == State.STREAM and _dir.y > 0.0:
				_dir = Vector2(signf(_dir.x) if _dir.x != 0.0 else 1.0, 0.0)
	_record_trail()
	_steer_bats(delta)


func _set_state(s: State) -> void:
	_state = s
	_t = 0.0


func _to_gather(time_scale := 1.0) -> void:
	_set_state(State.GATHER)
	_gather_for = randf_range(gather_time.x, gather_time.y) * time_scale


func _move_lead(target: Vector2, speed: float, delta: float) -> void:
	var want := (target - _lead).limit_length(speed)
	if (target - _lead).length() < 60.0:
		want = (target - _lead) * 2.0
	_lead_vel = _lead_vel.lerp(want, 1.0 - exp(-3.0 * delta))
	_lead += _lead_vel * delta


func _record_trail() -> void:
	_trail.append(_lead)
	_trail_in.append(1 if _in_canvas else 0)
	if _trail.size() > TRAIL_MAX:
		_trail = _trail.slice(_trail.size() - TRAIL_MAX)
		_trail_in = _trail_in.slice(_trail_in.size() - TRAIL_MAX)


## Point `back` frames ago on the leader's path (and whether it was in the canvas).
func _trail_at(back: int) -> int:
	return maxi(_trail.size() - 1 - back, 0)


func _streaming() -> bool:
	return _state == State.STREAM or _state == State.PAINT_RUN


func _steer_bats(delta: float) -> void:
	var stream := _streaming()
	for i in bats.size():
		var b = bats[i]
		b.tight_follow = stream
		if stream and not _trail.is_empty():
			# follow the leader's path, one after another
			var k := _trail_at((i + 1) * stream_gap_frames)
			b.desired = _trail[k] + Vector2(sin(_t * 9.0 + i) * 5.0, cos(_t * 7.0 + i) * 5.0)
			var in_canvas := _trail_in[k] == 1
			b.depth = move_toward(b.depth, paint_depth if in_canvas else 1.0, delta * 3.5)
			b.collision_layer = 0 if b.depth < 0.95 else 2
			if in_canvas and _state == State.PAINT_RUN:
				_rake(b)
			continue
		var o: Vector2 = _offsets[i].rotated(delta * (0.6 + 0.1 * (i % 3)))
		_offsets[i] = o
		var wobble := Vector2(sin(_t * 3.0 + i), cos(_t * 2.3 + i * 1.7)) * 10.0
		b.desired = _lead + o * _tight + wobble
		b.depth = move_toward(b.depth, 1.0, delta * 3.5)
		b.collision_layer = 2


func _begin_stream(at_player: bool) -> void:
	_trail.clear()
	_trail_in.clear()
	_last_stamp.clear()
	for b in bats:
		b.alert = false
		b.attacking = at_player
		b.hit_this_pass = false


func _end_stream() -> void:
	_in_canvas = false
	for b in bats:
		b.attacking = false
		b.tight_follow = false
	_side = -_side
	_to_gather()


func _spawn_bat() -> void:
	_spawned += 1
	var b := BatScene.instantiate()
	b.flock = self
	b.contact_damage = contact_damage
	b.position = FxLib.to_parent_space(get_parent(), global_position + Vector2(randf_range(-10, 10), randf_range(-20, 20)))
	b.velocity = Vector2.from_angle(randf_range(-PI, 0.0)) * randf_range(200.0, 380.0)
	b.died.connect(_on_bat_died.bind(b))
	get_parent().add_child(b)
	bats.append(b)
	_offsets.append(Vector2.from_angle(randf() * TAU) * sqrt(randf()) * flock_radius)
	FxLib.flash_light(get_parent(), global_position, warn_color, 1.0, 0.8, 0.12)


func _on_bat_died(b: Node2D) -> void:
	if game_data and is_instance_valid(b) and randf() < 0.5:
		game_data.spawn_drops(get_parent(), b.global_position, drop_table)


func _spread() -> float:
	if bats.is_empty():
		return 0.0
	var total := 0.0
	for b in bats:
		total += b.global_position.distance_to(_lead)
	return total / bats.size()


func _centroid() -> Vector2:
	if bats.is_empty():
		return _lead
	var c := Vector2.ZERO
	for b in bats:
		c += b.global_position
	return c / bats.size()


func _clamp_air(p: Vector2) -> Vector2:
	var nav := NavGraph.current
	if nav:
		var r: Rect2 = nav.air_rect()
		return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p


# ---------------------------------------------------------------- attack on the player

func _start_player_tell() -> void:
	_set_state(State.PLAYER_TELL)
	for b in bats:
		b.alert = true
	FxLib.flash_light(get_parent(), _lead, Color(1.0, 0.3, 0.35), 1.6, 2.0, tell_time)
	_screech(Color(1.0, 0.45, 0.5))


# ---------------------------------------------------------------- attack on the painting

## The cleanest visible spot of painting near the flock; false if none.
func _start_paint_tell() -> bool:
	var vp := get_viewport()
	var view := vp.get_visible_rect()
	var to_world := vp.get_canvas_transform().affine_inverse()
	var best := {}
	var best_value := INF
	for attempt in 8:
		var screen := view.position + Vector2(randf_range(0.2, 0.8) * view.size.x, randf_range(0.15, 0.45) * view.size.y)
		var pick := PaintPicker.pick(get_parent(), to_world * screen)
		if pick.is_empty():
			continue
		var layer = pick["layer"]
		var value: float = layer.distortion_at(pick["local"]) if layer.has_method("distortion_at") else 0.0
		value += (to_world * screen).distance_to(_lead) / 4000.0  # prefer nearby
		if value < best_value:
			best_value = value
			best = pick
	if best.is_empty():
		return false
	_entry = (best["layer"] as Node2D).to_global(best["local"])
	_dir = Vector2(1.0 if _entry.x > _lead.x else -1.0, randf_range(-0.25, 0.25)).normalized()
	_set_state(State.PAINT_TELL)
	for b in bats:
		b.alert = true
	FxLib.flash_light(get_parent(), _entry, warn_color, 1.2, 2.5, paint_tell_time)
	_screech(warn_color)
	return true


func _update_paint_run(delta: float) -> void:
	match _run_phase:
		0:  # dive at the entry point
			var to := _entry - _lead
			_lead_vel = to.normalized() * pass_speed
			_lead += _lead_vel * delta
			if to.length() < pass_speed * delta * 1.5:
				_lead = _entry
				_in_canvas = true
				_run_from = _lead
				_run_phase = 1
				_ripple(_entry)
		1:  # rake across the canvas
			_lead_vel = _dir * paint_speed + Vector2(0, sin(_t * 5.0) * 60.0)
			_lead += _lead_vel * delta
			if _lead.distance_to(_run_from) >= paint_length:
				_in_canvas = false
				_run_phase = 2
				_t = 0.0
				_ripple(_lead)
		2:  # climb back out; done when the last bat is out
			_lead_vel = _lead_vel.lerp(Vector2(_dir.x * 200.0, -320.0), 1.0 - exp(-4.0 * delta))
			_lead += _lead_vel * delta
			if _t >= 0.4 + bats.size() * stream_gap_frames / 60.0:
				_end_stream()


## One bat inside the canvas: a claw scratch every paint_step px of its path.
func _rake(b: Node2D) -> void:
	var last: Vector2 = _last_stamp.get(b, Vector2.INF)
	if last.distance_to(b.global_position) < paint_step:
		return
	_last_stamp[b] = b.global_position
	var pick := PaintPicker.pick(get_parent(), b.global_position)
	if pick.is_empty():
		return
	Paint.hit(self, pick["layer"], pick["local"], paint_radius, paint_strength, Paint.Kind.SCRATCH, &"bats")
	var marks := ClawMarks.new()
	marks.dir = _dir
	marks.size = paint_radius * 0.8
	marks.color = scratch_color
	marks.position = pick["local"]
	marks.z_as_relative = false
	marks.z_index = 1   # over every painting layer
	(pick["layer"] as Node).add_child(marks)


## The canvas "surface" breaking where the stream goes in / comes out.
func _ripple(at: Vector2) -> void:
	FxLib.flash_light(get_parent(), at, warn_color, 1.6, 1.6, 0.3)
	FxLib.burst(get_parent(), {
		"amount": 18, "life": 0.45, "v_min": 120.0, "v_max": 220.0, "emit_radius": 6.0,
		"texture": FxLib.glow(), "s_min": 0.05, "s_max": 0.1, "damp_min": 200.0, "damp_max": 300.0,
		"ramp": FxLib.fade_ramp(warn_color), "additive": true, "curve": null,
	}, at)


func _screech(color: Color) -> void:
	FxLib.burst(get_parent(), {
		"amount": 10, "life": 0.4, "v_min": 60.0, "v_max": 160.0,
		"texture": FxLib.streak(), "align": true, "angle_min": 0.0, "angle_max": 0.0,
		"spin_min": 0.0, "spin_max": 0.0, "s_min": 0.15, "s_max": 0.3,
		"ramp": FxLib.fade_ramp(color), "additive": true,
	}, _lead)


# ---------------------------------------------------------------- scatter / end

func scatter(from: Vector2) -> void:
	if _state in [State.WARN, State.EMERGE, State.DONE]:
		return
	_in_canvas = false
	for b in bats:
		b.attacking = false
		b.alert = false
		b.tight_follow = false
		b.depth = 1.0
		b.collision_layer = 2
		var d: float = b.global_position.distance_to(from)
		b.knock_away(from, scatter_strength * clampf(1.4 - d / 300.0, 0.4, 1.4))
	_lead_vel = (_lead - from).normalized() * 200.0
	_set_state(State.SCATTER)


func _finish() -> void:
	_state = State.DONE
	died.emit()
	queue_free()


# ---------------------------------------------------------------- warning glow

func _process(_delta: float) -> void:
	if _state in [State.WARN, State.EMERGE]:
		queue_redraw()
	elif _state == State.GATHER and _t < 0.1:
		queue_redraw()


func _draw() -> void:
	if not (_state in [State.WARN, State.EMERGE]):
		return
	var k := clampf(_t / warn_time, 0.0, 1.0) if _state == State.WARN else 1.0 - clampf(_t / emerge_time, 0.0, 1.0)
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.02)
	for i in 4:
		var r := (14.0 + i * 10.0) * k * pulse
		draw_circle(Vector2.ZERO, r, Color(warn_color, 0.18 * k))
	draw_circle(Vector2.ZERO, 6.0 * k, Color(1, 0.9, 1, 0.8 * k))
