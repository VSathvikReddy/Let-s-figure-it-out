extends Node2D
## Hold "attack": an arc grows clockwise, centred on the mouse direction.
## Release: the brush swings across the arc, the arc expands and fades,
## and everything in the final sector gets hit.
##
## Scene layout:
##   BrushAttack (this script)
##   ├─ Brush (Node2D)             <- rotated by the script
##   │   └─ Sprite2D               <- holds the art correction
##   ├─ HurtBox (Area2D)           <- set collision mask to your enemy layer
##   │   └─ CollisionPolygon2D     <- leave empty, the script fills it
##   └─ HitSound (AudioStreamPlayer2D)

const CHASE_SHARPNESS := 12.0
@export var damage := 1

@export var radius := 160.0
@export var radmin := 40.0
@export var radmax := 640.0
@export var radGM := 160.0
@export var charge_speed := 10.0
@export var min_sweep := 0.1
@export var max_sweep := PI
@export var brush_distance := 120.0
@export var shockwave_time := 0.35

@export var color_gradient: Gradient    # optional, white if left empty

const Effects := preload("res://compined/common/effects.gd")

## Off = the brush follows the mouse but cannot attack (the veil turns it off).
var enabled := true:
	set(v):
		enabled = v
		if not v and state == State.CHARGING:
			_finish()   # drop a half-charged swing

@onready var hurtbox: Area2D = $HurtBox
@onready var poly: CollisionPolygon2D = $HurtBox/CollisionPolygon2D
@onready var brush: Node2D = $Brush
@onready var sword_sound: AudioStreamPlayer2D = $HitSound

enum State { IDLE, CHARGING, RELEASING }
var state := State.IDLE

var chase_angle := 0.0
var sweep := 0.0
var wave_t := 0.0
var arc_alpha := 1.0
var chase_sharpness := CHASE_SHARPNESS
var radupto := 0.0
var radfrom := 0.0
var shock_start_angle := 0.0
var _draw_radius := 0.0


func _ready() -> void:
	hurtbox.monitoring = false
	radupto = radius
	radfrom = radius
	_draw_radius = radius


func _process(delta: float) -> void:
	var mouse_angle := to_local(get_global_mouse_position()).angle()

	if state == State.IDLE:
		chase_angle = mouse_angle
		if enabled and Input.is_action_just_pressed("attack"):
			state = State.CHARGING
			sweep = min_sweep
			wave_t = 0.0
			arc_alpha = 1.0
			chase_angle = mouse_angle - sweep / 2
	elif state == State.CHARGING:
		# grows fast at first and slows down near max_sweep
		sweep = minf(sweep + charge_speed * (max_sweep - sweep) / max_sweep * delta, max_sweep)
		chase_angle = mouse_angle - sweep / 2
		radius = lerpf(radGM, radmin, sweep / max_sweep)
		# "not pressed" instead of "just released": a click shorter than a frame
		# would otherwise leave the brush charging forever
		if not Input.is_action_pressed("attack"):
			chase_angle = mouse_angle + sweep / 2
			chase_sharpness *= 2
			_release()

	if state == State.CHARGING:
		brush.rotation = chase_angle
	else:
		brush.rotation = lerp_angle(brush.rotation, chase_angle, 1 - exp(-chase_sharpness * delta))
	brush.position = Vector2.from_angle(brush.rotation) * brush_distance

	if state != State.RELEASING:
		radupto = radGM * radGM / radius
		radfrom = radius
		shock_start_angle = brush.rotation
		_draw_radius = radius
	else:
		_draw_radius = lerpf(radfrom, radupto, wave_t)
	queue_redraw()


func _release() -> void:
	state = State.RELEASING

	# Hit area = the same sector that is drawn on screen.
	poly.polygon = _sector_points(radupto, shock_start_angle, sweep)
	_apply_damage()
	sword_sound.play()

	var tw := create_tween()
	tw.parallel().tween_property(self, "wave_t", 1.0, shockwave_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "arc_alpha", 0.0, shockwave_time)
	tw.tween_callback(_finish)


func _apply_damage() -> void:
	hurtbox.monitoring = true

	Effects.paint(hurtbox, 1)   # the brush brings the painting's detail back

	# Overlaps only update after a physics step, so wait for it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for target in hurtbox.get_overlapping_bodies() + hurtbox.get_overlapping_areas():
		if _can_hit(target):
			target.take_damage(damage)
	hurtbox.monitoring = false


func _can_hit(target: Node) -> bool:
	return target.has_method("take_damage") \
		and (target.is_in_group("enemy") or target.is_in_group("destructible"))


func _finish() -> void:
	state = State.IDLE
	wave_t = 0.0
	arc_alpha = 1.0
	radius = radGM
	chase_sharpness = CHASE_SHARPNESS


func _sector_points(r: float, from_angle: float, sweep_angle: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	var steps := maxi(4, int(ceil(sweep_angle / deg_to_rad(6.0))))
	for i in range(steps + 1):
		pts.append(Vector2.from_angle(from_angle + sweep_angle * i / steps) * r)
	return pts


func _draw() -> void:
	if state == State.IDLE:
		return
	var steps := maxi(8, int(sweep * 12.0))

	var c := Color.WHITE
	if color_gradient:
		c = color_gradient.sample(clampf(remap(_draw_radius, radmin, radmax, 0.0, 1.0), 0.0, 1.0))
	c.a = arc_alpha

	var from := shock_start_angle if state == State.RELEASING else brush.rotation
	draw_arc(Vector2.ZERO, _draw_radius, from, from + sweep, steps, c, 3.0, true)
