extends Node2D
class_name SectorAttack
## Hold "attack": an arc grows clockwise, centred on the mouse direction.
## Release: the brush swings across the arc, the arc expands and fades,
## and everything in the final sector gets hit.
##
## Scene layout:
##   BrushAttack (this script)
##   ├─ Brush (Node2D)             <- rotated by the script
##   │   └─ Sprite2D               <- holds the art correction
##   └─ Hitbox (Area2D)            <- set collision mask to your enemy layer
##       └─ CollisionPolygon2D     <- leave empty, the script fills it

const CHASE_SHARPNESS := 12.0
@export var damage :int= 1

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
@export var hit_window := 0.1

@onready var hurtbox: Area2D = $HurtBox
@onready var poly: CollisionPolygon2D = $HurtBox/CollisionPolygon2D
@onready var brush: Node2D = $Brush

enum State { IDLE, CHARGING, RELEASING }
var state := State.IDLE

var chase_angle := 0.0
var sweep := 0.0
var wave_t := 0.0
var arc_alpha := 1.0
var chase_sharpness := CHASE_SHARPNESS
var radupto := radius
var radfrom := radius
var shock_start_angle := 0.0

func _ready() -> void:
	hurtbox.monitoring = false

func _process(delta: float) -> void:
	var mouse_angle := to_local(get_global_mouse_position()).angle()

	if Input.is_action_just_pressed("attack") and state == State.IDLE:
		state = State.CHARGING
		sweep = min_sweep
		wave_t = 0.0
		arc_alpha = 1.0
		chase_angle = mouse_angle - sweep / 2
	elif state == State.CHARGING:
		sweep = minf(sweep + charge_speed * ((1 - exp(-(max_sweep - sweep) * delta)) / (1 - exp(-max_sweep * delta))) * delta, max_sweep)
		chase_angle = mouse_angle - sweep / 2
		radius = lerp(radGM, radmin, (1 - exp(-sweep * delta)) / (1 - exp(-max_sweep * delta)))
		if Input.is_action_just_released("attack"):
			chase_angle = mouse_angle + sweep / 2
			chase_sharpness *= 2
			_release()
	elif state == State.IDLE:
		chase_angle = mouse_angle

	if state == State.CHARGING:
		brush.rotation = chase_angle
	else:
		brush.rotation = lerp_angle(brush.rotation, chase_angle, 1 - exp(-chase_sharpness * delta))
	brush.position = Vector2.from_angle(brush.rotation) * brush_distance

	if state != State.RELEASING:
		radupto = radGM * radGM / radius
		radfrom = radius
		shock_start_angle = brush.rotation
	queue_redraw()

func _release() -> void:
	state = State.RELEASING

	# Hit area = the same sector that is drawn on screen.
	poly.polygon = _sector_points(radupto, shock_start_angle, sweep)
	_apply_damage()

	var tw := create_tween()
	tw.parallel().tween_property(self, "wave_t", 1.0, shockwave_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "arc_alpha", 0.0, shockwave_time)
	tw.tween_callback(_finish)

func _apply_damage() -> void:
	hurtbox.monitoring = true
	
	if PaintCanvas.can_paint():
		PaintCanvas.paint(hurtbox,1)
	
	# Overlaps only update after a physics step, so wait for it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for body in hurtbox.get_overlapping_bodies():
		if body.has_method("take_damage") and  ( body.is_in_group("enemy") or body.is_in_group("destructible") ):
			body.take_damage(damage)
	for area in hurtbox.get_overlapping_areas():
		if area.has_method("take_damage") and ( area.is_in_group("enemy") or area.is_in_group("destructible") ):
			area.take_damage(damage)
	hurtbox.monitoring = false

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
		c = color_gradient.sample(clampf(remap(radius, radmin, radmax, 0.0, 1.0), 0.0, 1.0))
	c.a = arc_alpha
	radius = lerpf(radfrom, radupto, wave_t)

	var from := shock_start_angle if state == State.RELEASING else brush.rotation
	draw_arc(Vector2.ZERO, radius, from, from + sweep, steps, c, 3.0, true)
