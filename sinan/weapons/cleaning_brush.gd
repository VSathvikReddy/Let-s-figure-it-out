extends "res://sinan/weapons/weapon.gd"
## The cleaning brush (after the team's charge-arc brush). Useless in a fight -
## it does no damage - but the best way to restore the painting.
## Hold either mouse button: an arc grows around you, centred on the mouse; the
## longer you hold, the wider it gets and the tighter it pulls in, which makes
## it reach further when you let go (reach = rad_start * rad_start / radius).
## Release: the brush sweeps across, the arc flies outward and restores the
## painting under it as it goes (spread over the sweep, not all in one frame).
## Skill tree: brush_reach (+reach), brush_charge (faster), brush_clean (+levels).

const CHASE_SHARPNESS := 12.0
## Spacing of the restore stamps along the arc (world px) and their radius.
const STAMP_STEP := 60.0
const STAMP_RADIUS := 52.0

@export var rad_start := 160.0
@export var rad_min := 40.0
@export var charge_speed := 10.0
@export var min_sweep := 0.1
@export var max_sweep := PI
@export var shockwave_time := 0.35
## Detail levels restored where the arc passes (Deep Clean adds to it).
@export var clean_strength := 0.5
## Milliseconds per frame the restore may take (the rest waits for the next
## frame), so a big sweep never stutters.
@export var restore_budget_ms := 3.0
@export var arc_color := Color(1.0, 0.95, 0.8)

enum State { IDLE, CHARGING, RELEASING }
var state := State.IDLE

var _radius := 160.0
var _sweep := 0.0
var _chase_angle := 0.0
var _chase := CHASE_SHARPNESS
var _wave := 0.0
var _alpha := 1.0
var _rad_to := 160.0
var _rad_from := 160.0
var _start_angle := 0.0
var _brush_angle := 0.0
var _center := Vector2.ZERO
var _stamped_to := 0.0   # how far out the restore has been stamped this sweep
var _queue: Array[Vector3] = []  # restore stamps waiting: (x, y, strength)


func _init() -> void:
	recoil_recover = 6.0


## The player calls this on click; the brush reads the buttons itself.
func fire(_player, _aim: Vector2, _painting: bool, _pick: Dictionary, _target: Vector2) -> void:
	pass


## No aim line: the arc is the preview.
func update_preview(guide, _aim: Vector2, _shooter: RID, _ready_shot: bool) -> void:
	if guide and guide.has_method("hide_preview"):
		guide.hide_preview()


func _process(delta: float) -> void:
	super._process(delta)
	var player := get_parent() as Node2D
	if player == null or (player.has_method("is_alive") and not player.is_alive()):
		return
	_center = player.global_position + Vector2(0, -55)
	var mouse_angle := (get_global_mouse_position() - _center).angle()
	var down := Input.is_action_pressed("fire") or Input.is_action_pressed("fire_paint")
	var reach := 1.0 + Progress.stat(&"brush_reach")
	var speed := charge_speed * (1.0 + Progress.stat(&"brush_charge"))

	_run_queue()
	match state:
		State.IDLE:
			_chase_angle = mouse_angle
			if down:
				state = State.CHARGING
				_sweep = min_sweep
				_wave = 0.0
				_alpha = 1.0
		State.CHARGING:
			_sweep = minf(_sweep + speed * ((1.0 - exp(-(max_sweep - _sweep) * delta)) / (1.0 - exp(-max_sweep * delta))) * delta, max_sweep)
			_radius = lerpf(rad_start, rad_min, (1.0 - exp(-_sweep * delta)) / (1.0 - exp(-max_sweep * delta))) * reach
			_chase_angle = mouse_angle - _sweep / 2.0
			if not down:
				_chase_angle = mouse_angle + _sweep / 2.0  # swing to the other end
				_chase *= 2.0
				_release()
		State.RELEASING:
			_radius = lerpf(_rad_from, _rad_to, _wave)
			_restore_out_to(_radius)

	if state == State.CHARGING:
		_brush_angle = _chase_angle
	else:
		_brush_angle = lerp_angle(_brush_angle, _chase_angle, 1.0 - exp(-_chase * delta))
	if state != State.RELEASING:
		_rad_to = rad_start * reach * rad_start * reach / maxf(_radius, 1.0)
		_rad_from = _radius
		_start_angle = _brush_angle


func _release() -> void:
	state = State.RELEASING
	_stamped_to = 30.0
	kick()
	var tw := create_tween()
	tw.parallel().tween_property(self, "_wave", 1.0, shockwave_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "_alpha", 0.0, shockwave_time)
	tw.tween_callback(_finish)
	get_tree().call_group("player", "add_trauma", 0.05)


## Restore the painting in rings out to radius `r` (rings already done are skipped).
func _restore_out_to(r: float) -> void:
	var strength := clean_strength + Progress.stat(&"brush_clean")
	while _stamped_to + STAMP_STEP <= r:
		_stamped_to += STAMP_STEP
		var count := maxi(1, ceili(_sweep * _stamped_to / STAMP_STEP))
		for i in count + 1:
			var p := _center + Vector2.from_angle(_start_angle + _sweep * float(i) / count) * _stamped_to
			_queue.append(Vector3(p.x, p.y, strength))


## Stamp queued restores until this frame's time budget is used up.
func _run_queue() -> void:
	var start := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - start < restore_budget_ms * 1000.0:
		var q: Vector3 = _queue.pop_front()
		Paint.hit_world(self, Vector2(q.x, q.y), STAMP_RADIUS, -q.z, Paint.Kind.RESTORE, &"brush")


func _finish() -> void:
	_restore_out_to(_rad_to)
	state = State.IDLE
	_wave = 0.0
	_alpha = 1.0
	_radius = rad_start
	_chase = CHASE_SHARPNESS


func _draw() -> void:
	# the brush itself, in the hand
	var kb := recoil * recoil
	var flip := signf(scale.y)
	draw_set_transform(Vector2(-kb * 14.0, sin(_t * 3.0) * 2.0), (-kb * 0.3 - spin) * flip, Vector2.ONE)
	draw_line(Vector2(-12, 0), Vector2(78, 0), Color(0.5, 0.3, 0.15), 7.0)
	draw_rect(Rect2(76, -7, 14, 14), Color(0.7, 0.7, 0.75))
	draw_colored_polygon(PackedVector2Array([Vector2(90, -8), Vector2(118, -4), Vector2(124, 0), Vector2(118, 4), Vector2(90, 8)]),
		Color(0.95, 0.9, 0.75))
	draw_colored_polygon(PackedVector2Array([Vector2(110, -3), Vector2(124, 0), Vector2(110, 3)]), Color(0.45, 0.6, 1.0))
	# the arc, drawn in world space around the player
	if state == State.IDLE:
		return
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	var from := _start_angle if state == State.RELEASING else _brush_angle
	var c := Color(arc_color, _alpha)
	var steps := maxi(8, int(_sweep * 12.0))
	draw_arc(_center, _radius, from, from + _sweep, steps, Color(c, _alpha * 0.25), 9.0, true)
	draw_arc(_center, _radius, from, from + _sweep, steps, c, 3.0, true)
	if state == State.CHARGING:
		# faint preview of how far the sweep will reach
		draw_arc(_center, _rad_to, from, from + _sweep, steps, Color(arc_color, 0.18), 1.5, true)
